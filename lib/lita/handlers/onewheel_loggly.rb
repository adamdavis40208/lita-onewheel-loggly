require 'json'
require 'rest-client'

module Lita
  module Handlers
    class OnewheelLoggly < Handler
      config :api_key, required: true
      config :base_uri, required: true
      config :query, required: true

      route /^logs\s+([\w-]+)$/i, :logs, command: true
      route /^logs$/i, :logs, command: true

      def logs(response)
        auth_header = {'Authorization': "bearer #{config.api_key}"}

        #   last_10_events_query = "/iterate?q=*&from=-10m&until=now&size=10"

        from_time = '-10m'
        if /\d+/.match response.matches[0][0]
          Lita.logger.debug "Suspected time: #{response.matches[0][0]}"
          from_time = response.matches[0][0]
          unless from_time[0] == '-'
            from_time = "-#{from_time}"
          end
        end

        response.reply "Gathering events from #{from_time}..."
        sample_query = "/iterate?q=#{CGI::escape config.query}&from=#{from_time}&until="
        uri = "#{config.base_uri}#{sample_query}"
        Lita.logger.debug uri
        resp = RestClient.get uri, auth_header

        alerts = {}

        events = JSON.parse resp.body
        alerts = process_event(events, alerts)
        events_count = events['events'].count
        Lita.logger.debug "events_count = #{events_count}"

        while events['next'] do
          Lita.logger.debug "Getting next #{events['next']}"
          resp = RestClient.get events['next'], auth_header
          events = JSON.parse resp.body
          events_count += events['events'].count
          Lita.logger.debug "events_count = #{events_count}"
          alerts = process_event(events, alerts)
        end

        Lita.logger.debug "#{events_count} events"
        response.reply "#{events_count} events"

        alerts = alerts.sort_by { |k, v| -v }
        alerts.each do |key, count|
          Lita.logger.debug "Counted #{count}: #{key}"
          response.reply "Counted #{count}: #{key}"
        end

      end

      def process_event(events, alerts)
        events['events'].each do |event|
          msg = JSON.parse event['logmsg']
          message = msg['message']
          if md = /(fault=[a-zA-Z0-9.-]+)/.match(message)
            alerts[md[0]] = init_or_increment alerts[md[0]]
          elsif /KeyError/.match(message)
            idx = message.index('KeyError')
            salient = message[idx - 120, 150]
            salient.gsub! /\\n - \w+/, ''
            alerts[salient] = init_or_increment alerts[salient]
          elsif /IndexError/.match(message)
            idx = message.index('IndexError')
            salient = message[idx - 120, 150]
            alerts[salient] = init_or_increment alerts[salient]
          elsif /NoneType/.match(message)
            idx = message.index('NoneType')
            salient = message[idx - 120, 150]
            alerts[salient] = init_or_increment alerts[salient]
          elsif md = /(socket\.timeout: The read operation timed out)/.match(message)
            salient = "Unhandled #{md[0]}"
            alerts[salient] = init_or_increment alerts[salient]
          elsif md = /(urllib3\.exceptions\.ProtocolError: \('Connection aborted\.', ConnectionResetError\(104, 'Connection reset by peer'\)\))/.match(message)
            salient = "Unhandled #{md[0]}"
            alerts[salient] = init_or_increment alerts[salient]
          elsif md = /(http\.client\.RemoteDisconnected: Remote end closed connection without response)/.match(message)
            salient = "Unhandled #{md[0]}"
            alerts[salient] = init_or_increment alerts[salient]
          elsif md = /(Could not extract locale from UsrLocale cookie. We got .* as UsrLocale cookie.)/.match(message)
            salient = md[0]
            alerts[salient] = init_or_increment alerts[salient]
          elsif md = /(requests.exceptions.TooManyRedirects: Exceeded 30 redirects.)/.match(message)
            salient = md[0]
            alerts[salient] = init_or_increment alerts[salient]
          elsif md = /(raise JSONDecodeError\("Expecting value", s, err.value\) from None)/.match(message)
            salient = "Unhandled #{md[0]}"
            alerts[salient] = init_or_increment alerts[salient]
          else
            md = /(x-amzn-requestid=[\w-]+)/.match(message)
            salient = message.gsub /\\n/, "\n"
            Lita.logger.debug "UNKNOWN #{salient}"

            alerts["Unknown #{md[0]}"] = 1
          end
        end
        alerts
      end

      def init_or_increment(thing)
        thing.to_i + 1
      end

      Lita.register_handler(self)
    end
  end
end
