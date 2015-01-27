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

  ws.on :open do |e|
    puts "Connected!"
    $battle_rooms = []
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
          battles = Utils::parse_battle_list JSON.parse(message[3]), TIER
          battles.each do |battle|
            unless $battle_rooms.include? battle
              puts "Joining #{battle}"
              ws.send("|/join #{battle}")
              $battle_rooms << battle
            end
          end
        end
      when "pm"
        unless Utils::condense_name(message[2][1..-1]) == Utils::condense_name(USERNAME) # if sent by the bot, ignore
          p message
          ws.send("|/w #{message[2]}, I'm a bot. Please PM my creator, Piccolo. He hangs out in Other Metas. If Piccolo isn't on, try Smogon (username: Piccolo Daimao)")
        end
      when "win" || "tie"
        ws.send("#{room}|/leave")
        puts "Leaving #{room}"
        $battle_rooms.delete(room)
      else
        puts "#{room}: #{message.inspect}" if room.start_with? "battle-#{TIER}-"
      end
    end
  end
  ws.on :close do |e|
    puts "Disconnected"
  end
end
