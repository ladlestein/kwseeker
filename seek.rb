require 'rubygems'
require 'bundler/setup'

require 'octokit'
require 'pstore'

# 
store = PStore.new("kw_seek.pstore")

client = Octokit::Client.new(:access_token => ENV['KWSEEKER_GITHUB_AUTH_TOKEN'])
user = client.user
user.login

events = client.repository_issue_events("joyent/node")

until client.last_response.rels[:next].nil?
  puts client.last_response.rels[:next].href
  store.transaction do 
    events.each {|event|
      store[event.id] = event
    }
  end
    
  events = client.get(client.last_response.rels[:next].href)
end

puts events.length

