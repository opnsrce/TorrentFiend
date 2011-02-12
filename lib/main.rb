##
# TorrentFiend by Levi Hackwith is licensed under a Creative Commons Attribution-NonCommercial-ShareAlike
# 3.0 United States License.
# For proper attribution, just put a link in your sourcecode or on your site back to http://www.levihackwith.com
# This software is offered 'as-is' and is for educational purposes only. If you do something stupid with it, don't come
# running to me.
##
require 'net/http';
require 'open-uri';
require 'rexml/document';
require 'sqlite3';
require 'net/http';
require 'uri';
require 'rexml/document';
require 'sqlite3';
##
# Downloads the torrent from the passed in URL
# @param string episode_id The ID of the epsiode being downloaded (e.g., 'Found S05E01')
# @param string torrent_url the URL of the torrent file to be downloaded
# @param integer [limit] The maximum number of redirects allowed to occur when downloading the file
# @returns boolean True on success or False on failure
##
def download_torrent(episode_id, torrent_url, limit = 10)
  # Check to make sure we haven't been trapped in an infinite loop
  if limit == 0 then
    puts "Too much redirection, skipping #{episode_id}";
    return true;
  else
    # Convert the URL of the torrent into a URI usable by Net:HTTP
    torrent_uri = URI.parse(torrent_url);
    # Open a connection to the torrent URL
    Net::HTTP.get_response(torrent_uri) { |http|
      # Check to see if we were able to connect to the torrent URL
      case http
      # We connected just fine
      when Net::HTTPSuccess, Net::HTTPFound then
        # Create a torrent file to store the data in
        File.open("#{episode_id}.torrent", 'wb') { |torrent_file|
          # Write the torrent data to the torrent file
          torrent_file.write(http.body);
          # Close the torrent file
          torrent_file.close
          # Check to see if we've download a 'locked' torrent file (html) instead of a regular torrent (.torrent)
          if(File.exists?('download.torrent.html'))
            # Delete the html file
            File.delete('download_torrent.html');
            return false;
          else
            return true;
          end
        }
      when Net::HTTPRedirection then
          download_torrent(episode_id, http['location'], limit - 1);
      end
    }
  end
end
##
# Increments the last episode number for the passed in show
# @param db_connection object The database connection to fiend.db
# @param show_id The Id
# @return nil
##
def update_show_listing(db_connection, show_id)
    update_query = "
        UPDATE 
            shows
        SET
            last_episode = (last_episode + 1)
        WHERE
            id = #{show_id}
            
    ";
    db_connection.execute(update_query);
    return nil
end
# Create new SQLite3 database connection
db_connection = SQLite3::Database.new('fiend.db');
# Create the table for shows if it doesn't exist to prevent the app from crashing
create_table_query = '
    CREATE TABLE IF NOT EXISTS shows (
        id INTEGER PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        current_season INTEGER NOT NULL,
        last_episode INTEGER NOT NULL
    )
';
db_connection.execute(create_table_query);
# Make sure I can reference records in the query result by column name instead of index number
db_connection.results_as_hash = true;
# Grab all TV shows from the shows table
query = '
    SELECT
        id,
        name,
        current_season,
        last_episode
    FROM
        shows
    ORDER BY
        name
';
# Run through each record in the result set
db_connection.execute(query) { |show|
  # Pad the current season number with a zero for later user in a search query
  season = '%02d' % show['current_season'].to_s;
  # Calculate the next episode number and pad with a zero
  next_episode = '%02d' % (Integer(show['last_episode']) + 1).to_s;
  # Store the name of the show
  name = show['name'];
  # Generate the URL of the RSS feed that will hold the list of torrents
  feed_url = URI.encode("http://btjunkie.org/rss.xml?query=#{name} S#{season}E#{next_episode}&o=52");
  # Generate a simple string the denotes the show, season and episode number being retrieved
  episode_id = "#{name} S#{season}E#{next_episode}";
  puts "Loading feed for #{name}..";
  # Store the response from the download of the feed
  feed_download_response = Net::HTTP.get_response(URI.parse(feed_url));
  # Store the contents of the response (in this case, XML data)
  xml_data = feed_download_response.body;
  puts "Feed Loaded. Parsing items.."
  # Create a new REXML Document and pass in the XML from the Net::HTTP response
  doc = REXML::Document.new(xml_data);
  # Loop through each  in the feed
  doc.root.each_element('//item') { |item|
    # Find and store the URL of the torrent we wish to download
    torrent_url = item.elements['link'].text + '/download.torrent';
    puts "Downloading #{episode_id} from #{torrent_url}";
    if download_torrent(episode_id, torrent_url) == true then
      update_show_listing(db_connection, show['id']);
    end
    break;
  }
}