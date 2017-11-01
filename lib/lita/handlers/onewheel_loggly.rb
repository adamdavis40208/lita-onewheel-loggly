require 'json'
require 'rest-client'

module Lita
  module Handlers
    class OnewheelLoggly < Handler
      config :api_key, required: true
      config :base_uri, required: true
      config :query, required: true

      route /^logs\s+(\w+)$/i, :logs, command: true
      route /^logs$/i, :logs, command: true

      def logs(response)
        auth_header = {'Authorization': "bearer #{config.api_key}"}

        #   last_10_events_query = "/iterate?q=*&from=-10m&until=now&size=10"

        from_time = '-10m'
        if /\d+/.match response.matches[0][0]
          Lita.logger.debug "Suspected time: #{response.matches[0][0]}"
          from_time = response.matches[0][0]
          if from_time[0] == '-'
            from_time = "-#{from_time}"
          end
        end

        sample_query = "/iterate?q=#{CGI::escape config.query}&from=#{from_time}&until="
        uri = "#{config.base_uri}#{sample_query}"
        Lita.logger.debug uri
        resp = RestClient.get uri, auth_header

        alerts = {}

        events = JSON.parse resp.body

        events['events'].each do |event|
          msg = JSON.parse event['logmsg']
          message = msg['message']
          if md = /(fault=[a-zA-Z0-9.-]+)/.match(message)
            alerts[md[0]] = 0 unless alerts[md[0]]
            alerts[md[0]] += 1
          elsif /KeyError/.match(message)
            idx = message.index('KeyError')
            salient = message[idx - 120, 150]
            salient.gsub! /\\n - \w+/, ''
            alerts[salient] = 0 unless alerts[salient]
            alerts[salient] += 1
          elsif /IndexError/.match(message)
            idx = message.index('IndexError')
            salient = message[idx - 120, 150]
            alerts[salient] = 0 unless alerts[salient]
            alerts[salient] += 1
          elsif md = /(socket\.timeout: The read operation timed out)/.match(message)
            salient = "Unhandled #{md[0]}"
            alerts[salient] = 0 unless alerts[salient]
            alerts[salient] += 1
          elsif md = /(urllib3\.exceptions\.ProtocolError: \('Connection aborted\.', ConnectionResetError\(104, 'Connection reset by peer'\)\))/.match(message)
            salient = "Unhandled #{md[0]}"
            alerts[salient] = 0 unless alerts[salient]
            alerts[salient] += 1
          elsif md = /(http\.client\.RemoteDisconnected: Remote end closed connection without response)/.match(message)
            salient = "Unhandled #{md[0]}"
            alerts[salient] = 0 unless alerts[salient]
            alerts[salient] += 1
          else
            salient = message.gsub /\\n/, "\n"
            Lita.logger.debug salient
            salient = 'unknown'
            alerts[salient] = 0 unless alerts[salient]
            alerts[salient] += 1
          end
        end

        Lita.logger.debug "#{events['events'].count} events"
        response.reply "#{events['events'].count} events"

        alerts.each do |key, count|
          Lita.logger.debug "Counted #{count}: #{key}"
          response.reply "Counted #{count}: #{key}"
        end

      end

      Lita.register_handler(self)
    end
  end
end
