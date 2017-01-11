module GitHub
  module Utils
    def self.dump_to_file(file, content)
      if file.respond_to?(:write) then
        file.write(content)
      else
        file = File.open(file, 'w')
        file.write(content)
        file.close
      end
    end
  end
end
