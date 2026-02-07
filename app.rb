require 'bundler/setup'
Bundler.require

require 'sinatra/base'
require 'sinatra'
require 'json'
require 'net/http'
require 'rufus-scheduler'

class MCPAdapter < Sinatra::Base
  # Enable CORS for all routes
  before do
    headers 'Access-Control-Allow-Origin' => '*',
            'Access-Control-Allow-Methods' => ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
            'Access-Control-Allow-Headers' => 'Content-Type, Authorization, X-Requested-With',
            'Access-Control-Allow-Credentials' => 'true',
            'Access-Control-Max-Age' => '86400'
  end

  # Handle OPTIONS requests for CORS preflight
  options '*' do
    200
  end

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
      <head>
        <title>MCP Adapter</title>
        <style>
          body { font-family: Arial, sans-serif; padding: 20px; max-width: 800px; margin: 0 auto; }
          .status { padding: 10px; border-radius: 5px; margin: 10px 0; }
          .good { background-color: #d4edda; color: #155724; }
          .bad { background-color: #f8d7da; color: #721c24; }
          code { background-color: #f4f4f4; padding: 2px 5px; border-radius: 3px; font-family: monospace; }
          ul { line-height: 1.6; }
          .cors-info { background-color: #e7f3ff; color: #004085; padding: 10px; border-radius: 5px; margin: 15px 0; }
        </style>
      </head>
      <body>
        <h2>✅ MCP Adapter is Running</h2>
        
        <div class="cors-info">
          <strong>🔓 CORS Enabled:</strong> All origins allowed
        </div>
        
        <div class="status #{ENV['UPTIMEROBOT_API_KEY'] ? 'good' : 'bad'}">
          <strong>UptimeRobot API Key:</strong> #{api_key_set}
          #{ENV['UPTIMEROBOT_API_KEY'] ? 'Configured' : 'Not configured'}
        </div>
        
        <h3>Available Endpoints:</h3>
        <ul>
          <li>GET <code>/</code> - This status page</li>
          <li>GET <code>/healthz</code> - Health check endpoint</li>
          <li>POST <code>/v1/chat/completions</code> - OpenAI-compatible API endpoint</li>
          <li>POST <code>/chat</code> - Simple chat API endpoint</li>
          <li>OPTIONS <code>/*</code> - CORS preflight requests</li>
        </ul>
        
        <h3>CORS Headers:</h3>
        <ul>
          <li><code>Access-Control-Allow-Origin: *</code> (all origins)</li>
          <li><code>Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS</code></li>
          <li><code>Access-Control-Allow-Headers: Content-Type, Authorization, X-Requested-With</code></li>
          <li><code>Access-Control-Allow-Credentials: true</code></li>
          <li><code>Access-Control-Max-Age: 86400</code></li>
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
  # CORS TEST ENDPOINT
  # -------------------------
  get '/cors-test' do
    content_type :json
    {
      cors_enabled: true,
      timestamp: Time.now.to_i,
      message: 'CORS is enabled for this endpoint',
      allowed_origins: '*',
      allowed_methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
      headers: {
        'Access-Control-Allow-Origin' => '*',
        'Access-Control-Allow-Methods' => 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers' => 'Content-Type, Authorization, X-Requested-With',
        'Access-Control-Allow-Credentials' => 'true'
      }
    }.to_json
  end

  # -------------------------
  # STARTUP
  # -------------------------
  if __FILE__ == $0
    puts '=' * 50
    puts '🔓 MCP Adapter with CORS Starting...'
    puts "Port: #{ENV.fetch('PORT', 10000)}"
    puts "Bind: 0.0.0.0"
    puts "CORS: Enabled for all origins (*)"
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
