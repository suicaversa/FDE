require 'json'
require 'time'

def shellesc(str, opt = {})
  str = str.dup
  if opt[:erace]
    opt[:erace] = [opt[:erace]] unless Array === opt[:erace]
    opt[:erace].each do |i|
      case i
      when :ctrl   then str.gsub!(/[\x00-\x08\x0a-\x1f\x7f]/, '')
      when :hyphen then str.gsub!(/^-+/, '')
      else              str.gsub!(i, '')
      end
    end
  end
  str.gsub!(/[\!\"\$\&\'\(\)\*\,\:\;\<\=\>\?\[\\\]\^\`\{\|\}\t ]/, '\\\\\\&')
  str
end

exit 1 if ARGV[0].nil?

map_json = JSON.parse File.open(ARGV[0],'r').read

map_json.each do |m|
  command = ''

  place_name = "#{shellesc(m['name'])}-#{m['latitude']}-#{m['longitude']}"
  post_date = "#{(Time.parse(m['created_time'])+9*60*60).strftime('%Y-%m-%d')}"

  command += "mkdir -p #{place_name}/#{post_date}_#{m['id']}\n"
  command += "cd #{place_name}/#{post_date}_#{m['id']}\n"
  m["images"].each do |i|
    command += "wget \"#{i}\"\n"
    command += "sleep 0.5\n"
  end
  command += "cd ../../"

  puts command
end
