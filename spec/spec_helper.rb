require 'uri'
require 'socket'

require 'faraday-http-cache'
require 'active_support/core_ext/date/calculations'
require 'active_support/core_ext/numeric/time'
require 'yajl'

require 'server'

host = 'localhost'
port = begin
  server = TCPServer.new(host, 0)
  server.addr[1]
ensure
  server.close if server
end


ENV['FARADAY_SERVER'] = "http://#{host}:#{port}"
ENV['FARADAY_ADAPTER'] ||= 'net_http'

pid = fork do
  require 'webrick'
  log = File.open('log/test.log', 'w+')
  log.sync = true
  webrick_opts = {
   :Port => port, :Logger => WEBrick::Log::new(log),
   :AccessLog => [[log, "[%{X-Faraday-Adapter}i] %m  %U  ->  %s %b"]]
  }
  Rack::Handler::WEBrick.run(Server, webrick_opts)
end

require 'net/http'
conn = Net::HTTP.new host, port
conn.open_timeout = conn.read_timeout = 0.1

responsive = lambda { |path|
  begin
    res = conn.start { conn.get(path) }
    res.is_a?(Net::HTTPSuccess)
  rescue Errno::ECONNREFUSED, Errno::EBADF, Timeout::Error, Net::HTTPBadResponse
    false
  end
}

server_pings = 0
begin
  server_pings += 1
  sleep 0.05
  abort "test server didn't manage to start" if server_pings >= 50
end until responsive.call('/ping')

RSpec.configure do |config|
  config.treat_symbols_as_metadata_keys_with_true_values = true
  config.run_all_when_everything_filtered = true
  config.filter_run :focus

  config.after(:suite) do
    `kill -9 #{pid}`
  end
end
