require 'goliath/request'
require 'goliath/response'

module Goliath
  class Connection < EM::Connection
    attr_accessor :app, :request, :response
    attr_reader :logger, :status, :config, :options

    AsyncResponse = [-1, {}, []].freeze

    def post_init
      self.request = Goliath::Request.new
      self.response = Goliath::Response.new

      self.request.remote_address = remote_address
      self.request.async_callback = method(:async_process)
    end

    def receive_data(data)
      request.parse(data)
      process if request.finished?
    end

    def process
      post_process(@app.call(@request.env))

    rescue Exception => e
      logger.error("#{e.message}\n#{e.backtrace.join("\n")}")
      post_process([500, {}, 'An error happened'])
    end

    def async_process(results)
      @response.status, @response.headers, @response.body = *results
      logger.info("Async status: #{@response.status}, " +
                  "Content-Length: #{@response.headers['Content-Length']}, " +
                  "Response Time: #{"%.2f" % ((Time.now.to_f - request.env[:start_time]) * 1000)}ms")

      send_response
      terminate_request
    end

    def post_process(results)
      results = results.to_a
      return if async_response?(results)

      @response.status, @response.headers, @response.body = *results
      logger.info("Sync body #{@response.body_str.inspect}") unless @response.status == 200
      logger.debug("nil body? really?") if @response.body.nil?

      send_response

    rescue Exception => e
      logger.error("#{e.message}\n#{e.backtrace.join("\n")}")

    ensure
      terminate_request unless async_response?(results)
    end

    def send_response
      @response.each { |chunk| send_data(chunk) }
    end

    def async_response?(results)
      results && results.first == AsyncResponse.first
    end

    def terminate_request
      close_connection_after_writing rescue nil
      close_request_response
    end

    def close_request_response
      @request.async_close.succeed
      @response.close rescue nil
    end

    def unbind
      @request.async_close.succeed unless @request.async_close.nil?
      @response.body.fail if @response.body.respond_to?(:fail)
    end

    def remote_address
      Socket.unpack_sockaddr_in(get_peername)[1]
    rescue Exception
      nil
    end

    def logger=(logger)
      @logger = logger
      self.request.logger = logger
    end

    def status=(status)
      @status = status
      self.request.status = status
    end

    def config=(config)
      @config = config
      self.request.config = config
    end

    def options=(options)
      @options = options
      self.request.options = options
    end
  end
end
