class Battle
  attr_reader :battle_id
  def initialize(battle)
    @battle_id = battle
    @path_to_file = "#{Dir.pwd}/data/#{battle}"
    @logfile = File.open(@path_to_file, "w")
  end

  def log(message)
    puts "#{@battle_id}: #{message}"
    @logfile.write(message + "\n")
  end

  def close
    @logfile.close
    battle_is_complete = false
    File.open(@path_to_file, "r") do |f|
      f.each_line do |line|
        if line.start_with? "|win|" or line.start_with? "|tie|"
          battle_is_complete = true
        end
      end
    end
    File.delete(@path_to_file) unless battle_is_complete
  end
end
