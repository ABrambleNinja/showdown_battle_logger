#!/usr/bin/env ruby
# Written by ABrambleNinja, based heavily on pickdenis's ps-chatbot <github.com/pickdenis/ps-chatbot>
# Released under MIT license, see LICENSE for details

CONFIG = "config.yml"

require 'faye/websocket'
require 'json'
require 'yaml'
require 'eventmachine'

require './battle'

unless File.exist? CONFIG
  puts "Error - no config file. Please copy config-example.yml to config.yml."
  exit
end

config = YAML.load(File.open(CONFIG))

TIER = config["tier"]
POLL_LENGTH = config["poll_length"]
SOCKET = config["socket"]

module Utils
  def self.parse_battle_list data, format
    battles = []
    data["rooms"].each do |key, value|
      if /^battle-#{format}-\d+$/.match(key) # if there's a battle that matches the correct format
        battles << key
      end
    end
    battles
  end

end

EM.run do
  ws = Faye::WebSocket::Client.new(SOCKET)
  joined_battles = []

  ws.on :open do |e|
    puts "Connected!"
    refresh_timer = EventMachine::PeriodicTimer.new(POLL_LENGTH) do
      ws.send("|/cmd roomlist")
    end
  end

  ws.on :message do |e|
    room = ""
    messages = e.data.split("\n")
    if messages[0][0] == '>'
      room = messages.shift[1..-1]
    end
    messages.each do |rawmessage|
      message = rawmessage.split("|")

      next if !message[1]

      case message[1].downcase
      when "queryresponse"
        if message[2] == "roomlist"
          battles = Utils::parse_battle_list(JSON.parse(message[3]), TIER) # get all battles that are of format TIER
          battles.each do |battle_id|
            unless joined_battles.any? {|joined_battle| joined_battle.battle_id == battle_id} # if we're not already in them
              puts "Joining #{battle_id}"
              ws.send("|/join #{battle_id}")
              joined_battles << Battle.new(battle_id)
            end
          end
        end
      when "c", "c:"
        # do nothing
      else
        battle = joined_battles.find {|joined_battle| joined_battle.battle_id == room}
        next if battle.nil?
        battle.log(message.join("|"))
        if message[1].downcase == "win" or message[1].downcase == "tie"
          puts "Leaving room #{room}"
          ws.send("#{room}|/leave")
          battle.close
          joined_battles.delete(battle)
        end
      end
    end
  end
  ws.on :close do |e|
    puts "Disconnected"
  end

  Signal.trap("INT") do
    joined_battles.each {|battle| battle.close }
    exit
  end
end
