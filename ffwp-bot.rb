# -*- coding: utf-8 -*-
MESHVIEWER_URI = "https://map.westpfalz.freifunk.net/meshviewer"
NICK = "ffwp-status"
CHANNEL = "#freifunk-westpfalz"
LOG_CHANNEL = "#freifunk-westpfalz.log"
STATS_FILE = "./ffwp-stats.json"
TIMEFORMAT = "%d.%m.%y %H:%M"
["time", "date", "json", "open-uri", "hashdiff", "cinch"].each{|gem| require gem}
bot = Cinch::Bot.new { configure {|c| c.server = "irc.freenode.org"; c.channels = [CHANNEL, LOG_CHANNEL]; c.nick = NICK}
  on :message, /^!highscore$/i do |m|
    m.reply highscore
  end
  on :message, /^!status$/i do |m|
    m.reply status
  end
  on :message, /^!help$/i do |m|
    m.reply "!status Liefert die aktuelle Anzahl an Knoten und Clients"
    m.reply "!highscore Liefert die Highscore für Knoten und Clients"
    m.reply "Du findest meinen Log in #{LOG_CHANNEL}"
  end }
log_channel = Cinch::Channel.new(LOG_CHANNEL,bot)
Thread.new { bot.start } ; sleep 1 until bot.channels.include?(CHANNEL)

def humanize secs
  [[60, "Sekunden"], [60, "Minuten"], [24, "Stunden"], [9999, "Tagen"]].map{ |count, name|
    if secs > 0
      secs, n = secs.divmod(count)
    end
    next if n.nil?
    "#{n.to_i} #{name}" }.compact.reverse.join(' ')
end

def highscore
  score = JSON.parse(File.read(STATS_FILE))
  "Der Highscore liegt bei #{score["nodes"]["count"]} Knoten (#{DateTime.parse(score["nodes"]["date"]).strftime TIMEFORMAT}) und #{score["clients"]["count"]} Clients (#{DateTime.parse(score["clients"]["date"]).strftime TIMEFORMAT})"
end

def status
  begin
    current_state = JSON.parse(URI.parse(MESHVIEWER_URI + '/nodes.json').read)['nodes']
  rescue JSON::ParserError => e
    e
  end
  stats = {"clients" => {"count" => 0, "date" => DateTime.now}, "nodes" => {"count" => 0, "date" => DateTime.now}}
  current_state.each{ |_ ,v| stats["clients"]["count"] += v["statistics"]["clients"].to_i}
  stats["nodes"]["count"] = current_state.select{ |_, v| v["flags"]["online"]}.count
  "Aktuell sind #{stats["nodes"]["count"]} Knoten und #{stats["clients"]["count"]} Clients online"
end

loop do
  begin
    current_state = JSON.parse(URI.parse(MESHVIEWER_URI + '/nodes.json').read)['nodes']
  rescue JSON::ParserError,
    Errno::ENETUNREACH,
    OpenURI::HTTPError => e
    next
  end
  @last_state ||= current_state
  current_state.each do |current|
    last = @last_state.select{|l| l == current[0]}.flatten
    next if last.empty?
    last = [last].to_h
    current = [current].to_h
    diffs = HashDiff.diff(last, current)
    hdiffs = diffs.map{ |diff|  [['flag', diff[0]], ['key', diff[1]], ['old', diff[2]], ['new', diff[3]], ['node', current[0]]].to_h
    }.delete_if{|h| h["key"] =~ /\.statistics\./ ||
                h["key"] =~ /\.lastseen$/ ||
      h["key"] =~ /\.nodeinfo\.network\.mesh_interfaces/ }
    hdiffs.each do |hdiff|
      case
      when hdiff["key"] =~ /\.flags\.online$/
        log_channel.send hdiff["new"] ?
        "#{last.first[1]["nodeinfo"]["hostname"]} ist jetzt online (Offline seit: #{humanize(Time.now - Time.now.utc_offset - Time.parse(last.first[1]["lastseen"]))}) #{MESHVIEWER_URI}/#!n:#{last.first[0]}" :
          "#{last.first[1]["nodeinfo"]["hostname"]} ist jetzt offline #{MESHVIEWER_URI}/#!n:#{last.first[0]}"
      when hdiff["key"] =~ /\.software\.autoupdater\.brach$/
        log_channel.send "#{last.first[1]["nodeinfo"]["hostname"]} hat den Update Branch gewechselt von (#{hdiff["old"]} -> #{hdiff["new"]}) #{MESHVIEWER_URI}/#!n:#{last.first[0]}"
      when hdiff["key"] =~ /\.software\.firmware\.release$/
        log_channel.send "#{last.first[1]["nodeinfo"]["hostname"]} hat eine neue Firmware installiert (#{hdiff["old"]} -> #{hdiff["new"]}) #{MESHVIEWER_URI}/#!n:#{last.first[0]}"
      else p hdiff
      end
    end
  end

  stats = {"clients" => {"count" => 0, "date" => DateTime.now}, "nodes" => {"count" => 0, "date" => DateTime.now}}
  File.write(STATS_FILE, stats.to_json) unless File.exist?(STATS_FILE)
  last_stats = JSON.parse(File.read(STATS_FILE))
  current_state.each{ |_ ,v| stats["clients"]["count"] += v["statistics"]["clients"].to_i}
  stats["nodes"]["count"] = current_state.select{ |_, v| v["flags"]["online"]}.count
  stats["clients"] = last_stats["clients"] if stats["clients"]["count"] <= last_stats["clients"]["count"]
  stats["nodes"] = last_stats["nodes"] if stats["nodes"]["count"] <= last_stats["nodes"]["count"]
  File.write(STATS_FILE, stats.to_json)
  @last_state = current_state.dup
  sleep 60
end
