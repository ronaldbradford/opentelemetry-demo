#!/usr/bin/env ruby
# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0
require 'rubygems'
require 'bundler/setup'
require 'faraday'
require 'opentelemetry/sdk'
require 'sinatra/base'
require 'json'

Bundler.require

ENV['OTEL_TRACES_EXPORTER'] ||= 'otlp'
ENV['OTEL_EXPORTER_OTLP_ENDPOINT'] ||= 'http://collector:4318'

OpenTelemetry::SDK.configure do |c|
   c.service_name = "lower"
   c.logger.level = Logger::DEBUG
   c.logger.debug("Using OTLP endpoint: #{ENV['OTEL_EXPORTER_OTLP_ENDPOINT']}")
   c.use_all
end


# Rack middleware to extract span context, create child span, and add
# attributes/events to the span
class OpenTelemetryMiddleware
  def initialize(app)
    @app = app
    @tracer = OpenTelemetry.tracer_provider.tracer('sinatra', '1.0')
  end

  def call(env)
    # Extract context from request headers
    context = OpenTelemetry.propagation.extract(
      env,
      getter: OpenTelemetry::Common::Propagation.rack_env_getter
    )

    status, headers, response_body = 200, {}, ''
    #OpenTelemetry.logger.debug("One more request #{env.inspect}")

    # Span name SHOULD be set to route:
    span_name = env['PATH_INFO']

    # For attribute naming, see
    # https://github.com/open-telemetry/opentelemetry-specification/blob/master/specification/data-semantic-conventions.md#http-server

    # Activate the extracted context
    OpenTelemetry::Context.with_current(context) do
      # Span kind MUST be `:server` for a HTTP server span
      @tracer.in_span(
        span_name,
        attributes: {
          'component' => 'http',
          'http.method' => env['REQUEST_METHOD'],
          'http.route' => env['PATH_INFO'],
          'http.url' => env['REQUEST_URI'],
        },
        kind: :server
      ) do |span|
        # Run application stack
        status, headers, response_body = @app.call(env)

        span.set_attribute('http.status_code', status)
      end
    end

    [status, headers, response_body]
  end
end

set :bind, '0.0.0.0'
set :port, 5000

use OpenTelemetryMiddleware
CHARS = ('a'..'z').to_a

get '/' do
  content_type :json
  c = CHARS.sample
  {char: c}.to_json
end
