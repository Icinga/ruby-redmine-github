require 'pandoc-ruby'

module Redmine
  module MarkdownConverter
    def self.convert(textile)
      raise Exception, 'Input is invalid' if textile.nil?
      textile = prepare(textile)
      json = PandocRuby.convert(textile, from: :textile, to: :json)
      json = fix_json(json)
      markdown = PandocRuby.convert(json, from: :json, to: :markdown_github)
      fix_markdown(markdown)
    end

    protected

    # The following functions are based on "convert_textile_to_markdown.rake"
    # @copyright (c) 2016 Adrien Crivelli <adrien.crivelli@gmail.com>
    # @source https://github.com/Ecodev/redmine_convert_textile_to_markown/blob/master/convert_textile_to_markdown.rake
    # @license MIT
    def self.prepare(textile)
      textile.strip!
      textile += "\n" # ensure final new line

      # Try to replace icingaweb2 stacktraces by code blocks
      textile.gsub!(/((?:^#\d+ .*?\r?\n)+)/m, "<pre>\n\\1</pre>\n")

      # Remove paragraph markup on start of lines
      textile.gsub!(/^p\([.\s]*/, '')

      # Drop table colspan/rowspan notation ("|\2." or "|/2.") because pandoc does not support it
      # See https://github.com/jgm/pandoc/issues/22
      textile.gsub!(/\|[\/\\]\d\. /, '| ')

      # Drop table alignement notation ("|>." or "|<." or "|=.") because pandoc does not support it
      # See https://github.com/jgm/pandoc/issues/22
      textile.gsub!(/\|[<>=]\. /, '| ')

      # Move the class from <code> to <pre> so pandoc can generate a code block with correct language
      textile.gsub!(/(<pre)(><code)( class="[^"]*")(>)/, '\\1\\3\\2\\4')

      # Inject a class in all <pre> that do not have a blank line before them
      # This is to force pandoc to use fenced code block (```) otherwise it would
      # use indented code block and would very likely need to insert an empty HTML
      # comment "<!-- -->" (see http://pandoc.org/README.html#ending-a-list)
      # which are unfortunately not supported by Redmine (see http://www.redmine.org/issues/20497)
      # TODO: needed?
      # tag_fenced_code_block = 'force-pandoc-to-ouput-fenced-code-block'
      # textile.gsub!(/([^\n]<pre)(>)/, "\\1 class=\"#{tag_fenced_code_block}\"\\2")

      # Force <pre> to have a blank line before them
      # Without this fix, a list of items containing <pre> would not be interpreted as a list at all.
      textile.gsub!(/([^\n])(<pre)/, "\\1\n\n\\2")

      # Some malformed textile content make pandoc run extremely slow,
      # so we convert it to proper textile before hitting pandoc
      # see https://github.com/jgm/pandoc/issues/3020
      textile.gsub!(/-          # (\d+)/, "* \\1")

      textile
    end

    def self.fix_markdown(markdown)
      # Remove the \ pandoc puts before * and > at begining of lines
      markdown.gsub!(/^((\\[*>])+)/) { $1.gsub("\\", '') }

      # Add a blank line before lists
      markdown.gsub!(/^([^*].*)\n\*/, "\\1\n\n*")

      # Remove the injected tag
      # TODO
      # markdown.gsub!(' ' + tag_fenced_code_block, '')

      # Un-escape Redmine link syntax to wiki pages
      # markdown.gsub!('\[\[', '[[')
      # markdown.gsub!('\]\]', ']]')

      # Un-escape Redmine quotation mark "> " that pandoc is not aware of
      # TODO: do markdown quote?
      # markdown.gsub!(/(^|\n)&gt; /, "\n> ")

      # Cleanup escaped hashes
      markdown.gsub!(/(http\S+)\\#(\S+)/, "\\1#\\2")

      # Remove commit: links, so GitHub can handle the bare commit id
      markdown.gsub!(/commit:(\S+\|)?([0-9a-f]{6,})/, "\\2")

      # Remove HTML formatting on quotations, Github supports it
      markdown.gsub!(/^#{Regexp.quote('&gt;')} ?/, '> ')

      markdown
    end

    # Working with Pandoc's AST
    def self.fix_json(json)
      pandoc = JSON.parse(json)

      pandoc_replace(pandoc)

      JSON.unparse(pandoc)
    rescue JSON::NestingError
      # we may not be able to replace something useful there...
      json
    end

    # Modifing elements in Pandoc's AST
    def self.pandoc_replace(pandoc)
      pandoc.each do |element|
        if element.is_a?(Array)
          pandoc_replace(element)
        elsif element.is_a?(Hash) && element.key?('t')
          case element['t']
            when 'Para'
              pandoc_replace(element['c'])
            when 'Str'
              # replace Str like '#12345.' with a link
              if element['c'] =~ /^\W*\\?#(\d+)\W*$/
                url = "#{Redmine.configuration.site}/issues/#{$1}"

                # replace reset the element to be a link
                element['t'] = 'Link'
                element['c'] = [
                  ['', [], []],
                  [{ t: 'Str', c: element['c'] }],
                  [url, '']
                ]
              end
            else
              # ignore
          end
        end
      end
    end
  end
end