module RedmineGithub
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

    def self.hash_symbolize(hash)
      hash.each_with_object({}) do |(k, v), memo|
        memo[k.to_sym] = v
        memo
      end
    end

    def self.hash_deep_symbolize(hash)
      hash = hash_symbolize(hash)

      hash.each_key do |key|
        hash[key] = hash_deep_symbolize(hash[key]) if hash[key].is_a?(Hash)
      end
    end

    def self.github_client(config)
      opts = { auto_pagination: true }
      opts.merge!(hash_symbolize(config['github']))
      Github.new(opts)
    end
  end
end
