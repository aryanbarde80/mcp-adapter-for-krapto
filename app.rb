require 'bundler/setup'
Bundler.require

require "sinatra"
require "json"
require "net/http"
require "rufus-scheduler"

set :bind, "0.0.0.0"
set :port, ENV.fetch("PORT", 10000)

# -------------------------
# BASIC HEALTH CHECK
# -------------------------
get "/" do
  "MCP Adapter is running"
end

# -------------------------
# OPENAI-COMPATIBLE ENDPOINT
# -------------------------
post "/v1/chat/completions" do
  request.body.rewind
  body = JSON.parse(request.body.read)

  user_message = body["messages"].last["content"]

  # TODO: replace with real MCP call
  mcp_reply = "MCP response for: #{user_message}"

  content_type :json
  {
    id: "chatcmpl-1",
    object: "chat.completion",
    choices: [
      {
        index: 0,
        message: {
          role: "assistant",
          content: mcp_reply
        }
      }
    ]
  }.to_json
end

# -------------------------
# KEEP-ALIVE SCHEDULER
# -------------------------
scheduler = Rufus::Scheduler.new

scheduler.every "14m" do
  begin
    uri = URI(ENV["SELF_URL"] || "http://localhost:#{ENV.fetch("PORT",10000)}")
    Net::HTTP.get(uri)
    puts "🔁 Self ping sent"
  rescue => e
    puts "Ping failed: #{e}"
  end
end
