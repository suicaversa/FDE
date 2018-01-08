require 'json'

def makeMapJSON(facebook_post)
  facebook_post.reject{ |j| j['place'].nil? }.map do |ppost|
    {
      id: ppost['id'],
      created_time: ppost['created_time'],
      message: ppost['message'],
      name: ppost['place']['name'],
      latitude: ppost['place']['location']['latitude'],
      longitude: ppost['place']['location']['longitude'],
      images: ppost['attachments']['data'].map do |sa|
        next if sa['type'] != 'photo' && sa['type'] != 'album'

        result = []
        result << sa['media']['image']['src'] if !sa['media'].nil? && !sa['media']['image'].nil?
        unless sa['subattachments'].nil?
          result += sa['subattachments']['data'].map do |s|
            'ERROR: media または media/imageがありません。' if s['media'].nil? || s['media']['image'].nil?
            s['media']['image']['src'] if !s['media'].nil? && !s['media']['image'].nil?
          end
        end
        result
      end.compact.flatten
    }
  end
end

facebook_post = JSON.parse File.open(ARGV[0],'r').read

puts JSON.pretty_generate(makeMapJSON(facebook_post))
