require 'bundler/setup'
Bundler.require

require 'sinatra/base'
require 'sinatra'
require 'json'
require 'net/http'
require 'rufus-scheduler'

class MCPAdapter < Sinatra::Base
  configure do
    set :port, ENV.fetch('PORT', 10000)
    set :bind, '0.0.0.0'
    set :server, :puma
    set :show_exceptions, false
    set :raise_errors, true
  end

  # -------------------------
  # HEALTH CHECK ENDPOINTS
  # -------------------------
  get '/' do
    api_key_set = ENV['UPTIMEROBOT_API_KEY'] ? '✅' : '❌'
    content_type :html
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head><title>MCP Adapter</title></head>
      <body style="font-family: Arial; padding: 20px;">
        <h2>✅ MCP Adapter is Running</h2>
        <p><strong>UptimeRobot API Key:</strong> #{api_key_set}</p>
        <p><strong>Endpoints:</strong></p>
        <ul>
          <li>GET <code>/healthz</code> - Health check</li>
          <li>POST <code>/v1/chat/completions</code> - OpenAI-compatible API</li>
          <li>POST <code>/chat</code> - Simple chat API</li>
        </ul>
        <p><em>Deployed: #{Time.now}</em></p>
      </body>
      </html>
    HTML
  end

  get '/healthz' do
    status 200
    content_type :text/plain
    'OK'
  end

  # -------------------------
  # UPTIMEROBOT MCP CLIENT
  # -------------------------
  def call_uptimerobot_mcp(user_message)
    api_key = ENV['UPTIMEROBOT_API_KEY']
    
    unless api_key
      return '❌ UptimeRobot API key not set in environment variables'
    end
    
    # Simple test response - API working check
    begin
      uri = URI('https://api.uptimerobot.com/v2/getMonitors')
      form_data = {
        api_key: api_key,
        format: 'json',
        logs: '0'
      }
      
      res = Net::HTTP.post(uri, form_data.to_json, 'Content-Type' => 'application/json')
      data = JSON.parse(res.body)
      
      if data['stat'] == 'ok'
        monitors = data['monitors'] || []
        up_count = monitors.count { |m| m['status'] == 2 }
        total_count = monitors.length
        
        return "🤖 **UptimeRobot Connected Successfully!**\n" +
               "• Monitors: #{total_count} total\n" +
               "• Status: #{up_count}/#{total_count} UP\n" +
               "• Your Query: \"#{user_message}\"\n\n" +
               "Ask me:\n" +
               "• \"Show my monitors\"\n" +
               "• \"Any incidents?\"\n" +
               "• \"Monitor status\""
      else
        return "❌ UptimeRobot API Error: #{data['error'] || 'Unknown error'}"
      end
    rescue => e
      return "⚠️ Connection Error: #{e.message}"
    end
  end

  # -------------------------
  # OPENAI-COMPATIBLE ENDPOINT
  # -------------------------
  post '/v1/chat/completions' do
    begin
      request.body.rewind
      body = JSON.parse(request.body.read)
      user_message = body.dig('messages', -1, 'content') || 'Hello'
      
      mcp_reply = call_uptimerobot_mcp(user_message)
      
      content_type :json
      {
        id: "chatcmpl-#{Time.now.to_i}",
        object: 'chat.completion',
        created: Time.now.to_i,
        choices: [{
          index: 0,
          message: {
            role: 'assistant',
            content: mcp_reply
          },
          finish_reason: 'stop'
        }]
      }.to_json
    rescue => e
      status 500
      content_type :json
      { error: e.message }.to_json
    end
  end

  # -------------------------
  # SIMPLE CHAT ENDPOINT
  # -------------------------
  post '/chat' do
    begin
      request.body.rewind
      data = JSON.parse(request.body.read)
      user_message = data['message'] || 'Hello'
      
      reply = call_uptimerobot_mcp(user_message)
      
      content_type :json
      { reply: reply }.to_json
    rescue => e
      status 500
      content_type :json
      { error: e.message }.to_json
    end
  end

  # -------------------------
  # STARTUP
  # -------------------------
  if __FILE__ == $0
    puts '=' * 50
    puts 'MCP Adapter Starting...'
    puts "Port: #{ENV.fetch('PORT', 10000)}"
    puts "UptimeRobot API: #{ENV['UPTIMEROBOT_API_KEY'] ? '✅ Set' : '❌ Not set'}"
    puts '=' * 50
    
    # Keep-alive scheduler
    scheduler = Rufus::Scheduler.new
    scheduler.every '14m' do
      begin
        uri = URI(ENV['SELF_URL'] || "http://localhost:#{ENV.fetch('PORT', 10000)}")
        Net::HTTP.get(uri)
        puts "🔁 Self ping sent at #{Time.now}"
      rescue => e
        puts "⚠️ Ping failed: #{e.message}"
      end
    end
    
    run!
  end
end
