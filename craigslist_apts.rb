# -*- coding: utf-8 -*-
require 'nokogiri'
require 'open-uri'
require 'geocoder'
require 'optparse'
require 'ostruct'

options = OpenStruct.new
options.query = [ ]
options.footage = 0

opt_parser = OptionParser.new do |opt|
  opt.banner = "Usage: craigslist_search [OPTIONS]"
  opt.separator  ""
  opt.separator  "Options"
  opt.on("-q", "--query QUERY", "which query you want to run") do |q|
    options.query << q
  end
  opt.on("-b", "--bedrooms BEDROOMS", "min number of beedrooms") do |b|
    options.bedrooms = b
  end
  opt.on("-p", "--price PRICE", "max price") do |b|
    options.price = b
  end
  opt.on("-f", "--footage SQUARE FOOTAGE", "min sq foot") do |b|
    options.footage = b.to_i
  end
  opt.on("-l", "--location LOCATION", "location to include") do |b|
    options.location = b
  end
  opt.on("-e", "--exclude-locations LOCATIONS", "location to exclude") do |b|
    options.exclude_locations = b
  end

  opt.on("-h","--help","help") do
    puts opt_parser
  end
end

opt_parser.parse!

max_price = options.price
min_bedrooms = options.bedrooms
if !options.query.empty?
  query = options.query
else
  query = [ '' ]
end

# bloomberg tech 37.7866751,-122.4021563
from_lat, from_lon = [ 37.7866751,-122.4021563 ]

Geocoder.configure(:units => :mi )

print <<-header
    <html>

      <head>

        <link rel="stylesheet" href="http://tablesorter.com/themes/blue/style.css" type="text/css" media="print, projection, screen" />
        <script type="text/javascript" src="http://ajax.googleapis.com/ajax/libs/jquery/1.8.0/jquery.min.js"></script>
        <script type="text/javascript" src="http://tablesorter.com/__jquery.tablesorter.min.js"></script>
        <script src="https://maps.googleapis.com/maps/api/js?v=3.exp&sensor=false"></script>

        <script type="text/javascript">
          $(document).ready(function() {
            $("#myTable").tablesorter();
          });
        </script>
        <style>
            table.tablesorter {
              font-size: 12pt;
            }
        </style>
      </head>

      <body>

    <div>Price: #{max_price}, Bedrooms: #{min_bedrooms}, Query: #{query}</div>
    <table id="myTable" class="tablesorter">
    <thead>
    <tr>
        <th>#</th>
        <th>Date</th>
        <th>Title</th>
        <th>Price</th>
        <th>Bedrooms</th>
        <th>Footage</th>
        <th>Dogs</th>
        <th>Distance</th>
        <th>Location</th>
        <th>Image</th>
        <th>Map</th>
    </tr>
    </thead>
    <tbody>
header

post_ids = {}
i = 1
query.each do |q|
  [ 0, 1, 2, 3, 4, 5 ].each do |skip|
    url = "http://sfbay.craigslist.org/search/apa?postal=94105&search_distance=10&s=#{skip}00&query=#{q}&min_price=2200&max_price=#{max_price}&bedrooms=#{min_bedrooms}&hasPic=1&availabilityMode=0&searchNearby=1"
    doc = Nokogiri::HTML(open(url))

    ####
    # Search for nodes by css
    doc.css('li.result-row').each do |p|
      link = p.css('.result-info a')[0]
      img = p.css('a.result-image')[0]['data-ids'].split(',')[0]
      loc = p.css('.result-hood').text
      next if post_ids[img]
      post_ids[img] = 1
      if img
        img = img.split(':')[1]
      end

      loc = loc.downcase.gsub(/\(|\)/, "").strip!
      if loc
        next if options.location and !loc.include? options.location
        next if options.exclude_locations and options.exclude_locations.downcase.include? loc
      end

      title = link.text
      next if /in.law/i.match(title)

      url = 'http://sfbay.craigslist.org' + link['href']

      date = p.css('time.result-date')[0]['datetime']
      price = p.css('span.result-price')[0].text
      if price =~ /\$/
        price = price.gsub(/\$/, '')
      end

      bedrooms, footage = p.css('.housing').text.split('-')
      bedrooms = /\d+/.match(bedrooms)
      if bedrooms
        bedrooms = bedrooms[0]
      end

      footage = /\d+/.match(footage)
      if footage
        footage = footage[0].to_i
      else
        footage = 1999
      end

      next if footage < options.footage

      dogs = ''

      begin
        post = Nokogiri::HTML(open(url))

        if /dogs are OK - wooof/i.match(post)
          dogs = 'OK'
        end

        m = /under\s+(\d+)\s*lbs|less\s+than\s+(\d+)\s*lbs/.match(post)

        if m
          dogs += ' ' + m[0]   
        end

        if /breeds/.match(post)
          dogs += ' breed restrictions'
        end

        if /no dogs?/i.match(post) or /no pets?/i.match(post)
          dogs = 'NO'
        end

        next if dogs == 'NO'

        description = post.css('#postingbody')[0]
        if description
          description = description.text.gsub(/QR Code Link to This Post/, "")
        end
      
        next if /in.law/i.match(description)

        map = post.css('#map')[0]
        if map 
          lat = map['data-latitude'].to_f
          lon = map['data-longitude'].to_f
        else
          lat = 0
          lon = 0
        end

        dist = Geocoder::Calculations.distance_between([ from_lat, from_lon ], [ lat, lon ] )
        next if dist > 10 and lat != 0 and lon != 0
      rescue => e
        lat = 0
        lon = 0
        dist = 1000
        description = e.message
      end

      printf('<tr>
            <td>%d</td>
            <td>%s</td>
            <td><p><a href="%s">%s</a></p><p>%s</p></td>
            <td>%s</td>
            <td>%s</td>
            <td>%s</td>
            <td>%s</td>
            <td>%.2f</td>
            <td>%s</td>
            <td><img src="http://images.craigslist.org/%s_300x300.jpg"></td>
            <td><img src="http://maps.googleapis.com/maps/api/staticmap?center=%f,%f&zoom=11&size=300x300&sensor=false&markers=color:blue%%7Clabel:X%%7C%f,%f"></td>
          </tr>
         ', i, date, url, title, description, price, bedrooms, footage, dogs, dist, loc, img, lat, lon, lat, lon)
      i = i + 1
    end
  end
end

print <<-footer
</tbody>
</body>
</html>
footer
