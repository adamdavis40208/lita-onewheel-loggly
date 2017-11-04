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
      route /^oneoff$/i, :oneoff, command: true
      route /^oneoffendeca$/i, :oneoff_endeca, command: true

      def logs(response)

        from_time = get_from_time(response.matches[0][0])

        total_request_count = get_total_request_count(from_time)

        uri = get_pagination_uri(from_time, response)
        events = call_loggly(uri)
        # Todo: Capture that exception, print and return

        alerts = Hash.new { |h, k| h[k] = 0 }
        alerts = process_event(events, alerts)

        events_count = events['events'].count
        Lita.logger.debug "events_count = #{events_count}"

        while events['next'] do
          events = call_loggly(events['next'])
          events_count += events['events'].count
          Lita.logger.debug "events_count = #{events_count}"

          alerts = process_event(events, alerts)
        end

        Lita.logger.debug "#{events_count} events"

        replies = "#{total_request_count} requests\n#{events_count} events\n"
        alerts = alerts.sort_by { |_k, v| -v }
        alerts.each do |key, count|
          Lita.logger.debug "Counted #{count}: #{key}"
          replies += "Counted #{count}: #{key}\n"
        end

        response.reply "```#{replies}```"
      end

      def get_from_time(from_time_param)
        from_time = '-10m'
        if /\d+/.match from_time_param
          Lita.logger.debug "Suspected time: #{from_time_param}"
          from_time = from_time_param
          unless from_time[0] == '-'
            from_time = "-#{from_time}"
          end
        end
        from_time
      end

      def get_total_request_count(from_time)
        # Getting the total events count is a texas two-step...
        query = '"translation--prod-" "request START"'
        uri = "http://lululemon.loggly.com/apiv2/search?q=#{CGI::escape query}&from=#{from_time}&until=now"

        rsid_response = call_loggly(uri)
        rsid = rsid_response['rsid']['id']

        events = call_loggly("http://lululemon.loggly.com/apiv2/events?rsid=#{rsid}")
        events['total_events']
      end

      def call_loggly(uri)
        begin
          auth_header = {'Authorization': "bearer #{config.api_key}"}
          Lita.logger.debug uri
          resp = RestClient.get uri, auth_header
        rescue StandardError => timeout_exception
          Lita.logger.debug "Error: #{timeout_exception}"
          return timeout_exception
        end
        JSON.parse resp.body
      end

      def get_pagination_uri(from_time, response)
        response.reply "Gathering `#{config.query}` events from #{from_time}..."
        sample_query = "/iterate?q=#{CGI::escape config.query}&from=#{from_time}&until=&size=1000"
        "#{config.base_uri}#{sample_query}"
      end

      def oneoff(response)
        auth_header = {'Authorization': "bearer #{config.api_key}"}

        query = '"translation--prod-" "status=404" -"return to FE"'
        sample_query = "/iterate?q=#{CGI::escape query}&from=2017-11-02T10:00:00Z&until=2017-11-03T16:00:00Z&size=1000"
        uri = "#{config.base_uri}#{sample_query}"
        Lita.logger.debug uri

        begin
          resp = RestClient.get uri, auth_header
        rescue Exception => timeout_exception
          response.reply "Error: #{timeout_exception}"
          return
        end

        alerts = Hash.new { |h, k| h[k] = 0 }

        master_events = []
        events = JSON.parse resp.body
        # alerts = process_event(events, alerts)
        events_count = events['events'].count
        Lita.logger.debug "events_count = #{events_count}"

        events['events'].each do |eve|
          master_events.push eve['event']['json']['message']
        end

        while events['next'] do
          Lita.logger.debug "Getting next #{events['next']}"
          resp = RestClient.get events['next'], auth_header
          events = JSON.parse resp.body
          events['events'].each do |eve|
            master_events.push eve['event']['json']['message']
          end
          # alerts = process_event(events, alerts)
        end

        Lita.logger.debug "#{events_count} events"
        response.reply "#{events_count} events"
        Lita.logger.debug "#{master_events.count} events"
        response.reply "#{master_events.count} events"

        url_list = []
        master_events.each do |message|
          if md = /,\s+url=([^,]+),/.match(message)
            Lita.logger.debug md.captures[0]
            url_list.push md.captures[0]
          end
        end

        url_list.each do |url|
          alerts[url] += 1
        end


        file = File.open("oneoff_report.csv", "w")
        # replies = ''
        alerts = alerts.sort_by { |_k, v| -v }
        alerts.each do |key, count|
          # Lita.logger.debug "Counted #{count}: #{key}"
          # replies += "Counted #{count}: #{key}\n"
          file.write("#{count},#{key}\n")
        end

        file.close
        response.reply "oneoff_report.csv created."
      end

      def oneoff_endeca(response)
        auth_header = {'Authorization': "bearer #{config.api_key}"}

        query = 'json.level:ERROR  ("call.endeca.malformed-resp-payload")'
        sample_query = "/iterate?q=#{CGI::escape query}&from=-12h&until=&size=1000"
        uri = "#{config.base_uri}#{sample_query}"
        Lita.logger.debug uri

        begin
          resp = RestClient.get uri, auth_header
        rescue Exception => timeout_exception
          response.reply "Error: #{timeout_exception}"
          return
        end

        alerts = Hash.new { |h, k| h[k] = 0 }

        master_events = []
        events = JSON.parse resp.body
        # alerts = process_event(events, alerts)
        events_count = events['events'].count
        Lita.logger.debug "events_count = #{events_count}"

        events['events'].each do |eve|
          master_events.push eve['event']['json']['message']
        end

        while events['next'] do
          Lita.logger.debug "Getting next #{events['next']}"
          resp = RestClient.get events['next'], auth_header
          events = JSON.parse resp.body
          events['events'].each do |eve|
            master_events.push eve['event']['json']['message']
          end
          # alerts = process_event(events, alerts)
        end

        Lita.logger.debug "#{events_count} events"
        response.reply "#{events_count} events"
        Lita.logger.debug "#{master_events.count} events"
        response.reply "#{master_events.count} events"

        url_list = []
        master_events.each do |message|
          if md = /,\s+req_url=([^,]+),/.match(message)
            Lita.logger.debug md.captures[0]
            url_list.push md.captures[0]
          end
        end

        url_list.each do |url|
          alerts[url] += 1
        end

        file = File.open("oneoff_endeca_report.csv", "w")
        # replies = ''
        alerts = alerts.sort_by { |_k, v| -v }
        alerts.each do |key, count|
          # Lita.logger.debug "Counted #{count}: #{key}"
          # replies += "Counted #{count}: #{key}\n"
          file.write("#{count},#{key}\n")
        end

        file.close
        response.reply "oneoff_endeca_report.csv created."
      end

      def process_event(events, alerts)
        events['events'].each do |event|
          msg = JSON.parse event['logmsg']
          message = msg['message']
          if md = /(fault=[a-zA-Z0-9.-]+)/.match(message)
            alerts[md[0]] += 1
          elsif /KeyError/.match(message)
            idx = message.index('KeyError')
            salient = message[idx - 120, 150]
            salient.gsub! /\\n - \w+/, ''
            alerts[salient] += 1
          elsif /IndexError/.match(message)
            idx = message.index('IndexError')
            salient = message[idx - 120, 150]
            alerts[salient] += 1
          elsif /NoneType/.match(message)
            idx = message.index('NoneType')
            salient = message[idx - 120, 150]
            alerts[salient] += 1
          elsif /SSLError/.match(message)
            idx = message.index('SSLError')
            salient = message[idx - 120, 170]
            alerts[salient] += 1
          elsif md = /(socket\.timeout: The read operation timed out)/.match(message)
            salient = "Unhandled #{md[0]}"
            alerts[salient] += 1
          elsif md = /(urllib3\.exceptions\.ProtocolError: \('Connection aborted\.', ConnectionResetError\(104, 'Connection reset by peer'\)\))/.match(message)
            salient = "Unhandled #{md[0]}"
            alerts[salient] += 1
          elsif md = /(http\.client\.RemoteDisconnected: Remote end closed connection without response)/.match(message)
            salient = "Unhandled #{md[0]}"
            alerts[salient] += 1
          elsif md = /(Could not extract locale from UsrLocale cookie. We got .* as UsrLocale cookie.)/.match(message)
            salient = md[0]
            alerts[salient] += 1
          elsif md = /(requests.exceptions.TooManyRedirects: Exceeded 30 redirects.)/.match(message)
            salient = md[0]
            alerts[salient] += 1
          elsif md = /(raise JSONDecodeError\("Expecting value", s, err.value\) from None)/.match(message)
            salient = "Unhandled #{md[0]}"
            alerts[salient] += 1
          elsif md = /(Got a cookie string but could not extract cookies.)/.match(message)
            salient = "Unhandled #{md[0]}"
            alerts[salient] += 1
          elsif md = /(requests.exceptions.ConnectTimeout.*Connection to shop.lululemon.com timed out.)/.match(message)
            salient = "Unhandled #{md[0]}"
            alerts[salient] += 1
          elsif md = /(requests.exceptions.ReadTimeout.*read timeout=\d+\))/.match(message)
            salient = "Unhandled #{md[0]}"
            alerts[salient] += 1
          else
            md = /(x-amzn-requestid=[\w-]+)/.match(message)
            salient = message.gsub /\\n/, "\n"
            Lita.logger.debug "UNKNOWN #{salient}"

            alerts["Unknown #{md[0]}"] = 1
          end
        end
        alerts
      end

      Lita.register_handler(self)
    end
  end
end
