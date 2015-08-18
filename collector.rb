#!/usr/bin/env ruby

CONFIG = "config.yml"

INITIAL_COMMANDS = [
  "|/avatar 51",
  "|/join othermetas"
] # commands to send upon login

require 'faye/websocket'
require 'net/http'
require 'uri'
require 'json'
require 'yaml'
require 'eventmachine'
require 'em-http-request'
require 'pry'

require './battle'

unless File.exist? CONFIG
  puts "Error - no config file. Please copy config-example.yml to config.yml."
  exit
end

config = YAML.load(File.open(CONFIG))

USERNAME = config["username"]
PASSWORD = config["password"]
TIER = config["tier"]
POLL_LENGTH = config["poll_length"]
SOCKET = config["socket"]

module Utils
  def self.login name, pass, challenge, challengekeyid, &callback
    EM::HttpRequest.new("https://play.pokemonshowdown.com/action.php").post(body: {
      'act' => 'login',
      'name' => name,
      'pass' => pass,
      'challengekeyid' => challengekeyid.to_i,
      'challenge' => challenge} ).callback { |http|

      callback.call(JSON.parse(http.response[1..-1])["assertion"]) # PS returns a ']' before the json
    }
  end

  def self.condense_name name
    name.downcase.gsub(/[^A-Za-z0-9]/, '')
  end

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
      when "challstr"
        Utils::login(USERNAME, PASSWORD, message[3], message[2]) do |assertion|
          if assertion.nil?
            raise "Could not login."
          end

          ws.send("|/trn #{USERNAME},0,#{assertion}")
        end
      when "updateuser"
        if Utils::condense_name(message[2]) == Utils::condense_name(USERNAME)
          puts "Successfully logged in as #{USERNAME}."
          INITIAL_COMMANDS.each do |command|
            puts "Running command: #{command}"
            ws.send(command)
          end

          refresh_timer = EventMachine::PeriodicTimer.new(POLL_LENGTH) do
            ws.send("|/cmd roomlist")
          end
        else
          puts "Error logging in: #{message[2]}"
        end
      when "queryresponse"
        if message[2] == "roomlist"
          battles = Utils::parse_battle_list(JSON.parse(message[3]), TIER)
          battles.each do |battle_id|
            unless joined_battles.any? {|joined_battle| joined_battle.battle_id == battle_id}
              puts "Joining #{battle_id}"
              ws.send("|/join #{battle_id}")
              joined_battles << Battle.new(battle_id)
            end
          end
        end
      when "pm"
        unless Utils::condense_name(message[2][1..-1]) == Utils::condense_name(USERNAME) # if sent by the bot, ignore
          invite = false
          content = message[4].split(" ")
          if (content[0] == "/invite")
            if (content.length > 1)
              ws.send("|/join #{content[1]}")
              invite = true
            end
          end
          ws.send("|/w #{message[2]}, I'm a bot. Please PM my creator, Piccolo. He hangs out in Other Metas. If Piccolo isn't on, try Smogon (username: Piccolo Daimao)") unless invite
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
