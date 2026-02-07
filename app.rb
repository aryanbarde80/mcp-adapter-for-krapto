require 'bundler/setup'
Bundler.require

require "sinatra"
require "json"
require "net/http"
require "rufus-scheduler"

set :bind, "0.0.0.0"
set :port, ENV.fetch("PORT", 10000)

# -------------------------
# UPTIMEROBOT MCP CLIENT
# -------------------------
def call_uptimerobot_mcp(user_message)
  api_key = ENV["UPTIMEROBOT_API_KEY"]
  
  unless api_key
    return "❌ UptimeRobot API key not set in environment variables"
  end
  
  # Extract intent from user message
  intent = user_message.downcase
  
  begin
    # Call UptimeRobot API based on intent
    if intent.include?("monitor") || intent.include?("list") || intent.include?("show")
      # Get all monitors
      uri = URI("https://api.uptimerobot.com/v2/getMonitors")
      form_data = {
        api_key: api_key,
        format: "json",
        logs: "1"
      }
      
      res = Net::HTTP.post(uri, form_data.to_json, "Content-Type" => "application/json")
      data = JSON.parse(res.body)
      
      if data["stat"] == "ok"
        monitors = data["monitors"]
        
        # Count by status
        up_count = monitors.count { |m| m["status"] == 2 }
        down_count = monitors.count { |m| m["status"] == 9 }
        paused_count = monitors.count { |m| m["status"] == 0 }
        
        summary = "📊 **UptimeRobot Monitors Summary:**\n"
        summary += "• Total Monitors: #{monitors.length}\n"
        summary += "• ✅ UP: #{up_count}\n"
        summary += "• ❌ DOWN: #{down_count}\n"
        summary += "• ⏸️ PAUSED: #{paused_count}\n\n"
        
        # List top 5 monitors
        summary += "**Recent Monitors:**\n"
        monitors.first(5).each do |monitor|
          status_emoji = case monitor["status"]
            when 2 then "✅"
            when 9 then "❌"
            when 0 then "⏸️"
            else "❓"
          end
          
          summary += "#{status_emoji} #{monitor["friendly_name"] || monitor["url"]}\n"
        end
        
        if monitors.length > 5
          summary += "\n...and #{monitors.length - 5} more monitors."
        end
        
        return summary
      else
        return "❌ UptimeRobot API error: #{data["error"] || "Unknown error"}"
      end
      
    elsif intent.include?("incident") || intent.include?("alert") || intent.include?("problem")
      # Get incidents
      uri = URI("https://api.uptimerobot.com/v2/getMonitors")
      form_data = {
        api_key: api_key,
        format: "json",
        response_times: "1",
        response_times_limit: "5"
      }
      
      res = Net::HTTP.post(uri, form_data.to_json, "Content-Type" => "application/json")
      data = JSON.parse(res.body)
      
      if data["stat"] == "ok"
        down_monitors = data["monitors"].select { |m| m["status"] == 9 }
        
        if down_monitors.empty?
          return "🎉 **No current incidents!** All monitors are running normally."
        else
          summary = "🚨 **Active Incidents (#{down_monitors.length}):**\n"
          
          down_monitors.each do |monitor|
            duration = monitor["duration"] ? (monitor["duration"] / 60).to_i : 0
            summary += "• #{monitor["friendly_name"] || monitor["url"]} - Down for #{duration} minutes\n"
          end
          
          return summary
        end
      else
        return "❌ UptimeRobot API error: #{data["error"] || "Unknown error"}"
      end
      
    else
      # Default response - show monitor status
      uri = URI("https://api.uptimerobot.com/v2/getMonitors")
      form_data = {
        api_key: api_key,
        format: "json"
      }
      
      res = Net::HTTP.post(uri, form_data.to_json, "Content-Type" => "application/json")
      data = JSON.parse(res.body)
      
      if data["stat"] == "ok"
        total = data["monitors"].length
        up = data["monitors"].count { |m| m["status"] == 2 }
        
        return "🤖 **UptimeRobot Status:**\n• #{up}/#{total} monitors are UP\n• Query: \"#{user_message}\"\n\nYou can ask me:\n• \"Show me my monitors\"\n• \"Any incidents?\"\n• \"Monitor status\""
      else
        return "❌ UptimeRobot API error: #{data["error"] || "Unknown error"}"
      end
    end
    
  rescue SocketError, Net::OpenTimeout => e
    return "🌐 **Network Error:** Could not connect to UptimeRobot API. Please check your internet connection."
  rescue JSON::ParserError => e
    return "📄 **Response Error:** Could not parse UptimeRobot response."
  rescue => e
    return "⚠️ **Unexpected Error:** #{e.message}"
  end
end

# -------------------------
# BASIC HEALTH CHECK
# -------------------------
get "/" do
  api_key_set = ENV["UPTIMEROBOT_API_KEY"] ? "✅" : "❌"
  "<h3>MCP Adapter is running</h3>
   <p>UptimeRobot API Key: #{api_key_set}</p>
   <p>Test endpoint: POST /v1/chat/completions</p>
   <p>Deployed: #{Time.now}</p>"
end

# -------------------------
# OPENAI-COMPATIBLE ENDPOINT
# -------------------------
post "/v1/chat/completions" do
  request.body.rewind
  body = JSON.parse(request.body.read)

  user_message = body["messages"].last["content"]
  
  # Get response from UptimeRobot
  mcp_reply = call_uptimerobot_mcp(user_message)

  content_type :json
  {
    id: "chatcmpl-#{Time.now.to_i}",
    object: "chat.completion",
    created: Time.now.to_i,
    choices: [
      {
        index: 0,
        message: {
          role: "assistant",
          content: mcp_reply
        },
        finish_reason: "stop"
      }
    ],
    usage: {
      prompt_tokens: user_message.length / 4,
      completion_tokens: mcp_reply.length / 4,
      total_tokens: (user_message.length + mcp_reply.length) / 4
    }
  }.to_json
end

# -------------------------
# SIMPLE CHAT ENDPOINT (optional)
# -------------------------
post "/chat" do
  request.body.rewind
  data = JSON.parse(request.body.read)
  
  user_message = data["message"]
  reply = call_uptimerobot_mcp(user_message)
  
  content_type :json
  { reply: reply }.to_json
end

# -------------------------
# KEEP-ALIVE SCHEDULER
# -------------------------
scheduler = Rufus::Scheduler.new

scheduler.every "14m" do
  begin
    uri = URI(ENV["SELF_URL"] || "http://localhost:#{ENV.fetch("PORT",10000)}")
    Net::HTTP.get(uri)
    puts "🔁 Self ping sent at #{Time.now}"
  rescue => e
    puts "⚠️ Ping failed: #{e.message}"
  end
end

# -------------------------
# STARTUP MESSAGE
# -------------------------
puts "=" * 50
puts "MCP Adapter Started!"
puts "Port: #{ENV.fetch("PORT", 10000)}"
puts "UptimeRobot API: #{ENV["UPTIMEROBOT_API_KEY"] ? "✅ Set" : "❌ Not set"}"
puts "Self URL: #{ENV["SELF_URL"] || "Not configured"}"
puts "=" * 50
