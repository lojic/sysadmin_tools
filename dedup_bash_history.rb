#!/usr/bin/env ruby

# Copyright (C) 2011 by Brian J. Adkins
#
# NOTE: Run from home directory
#
# This program will eliminate duplicate lines in .bash_history and
# keep the last of any duplicates. For example:
#
# Before:
#
# ls
# echo "hello"
# ls
# cat foo.txt
# cat foo.txt
# ls
# echo "hello
#
# After:
#
# cat foo.txt
# ls
# echo "hello

BACKUP_FILE  = '.bash_history_backup'
HISTORY_FILE = '.bash_history'
TEMP_FILE    = '.bash_history_temp'

`cp #{HISTORY_FILE} #{BACKUP_FILE}`

File.open(HISTORY_FILE, "r") do |hist_file|
  File.open(TEMP_FILE, "w") do |temp_file|
    hist_file.readlines.reverse.uniq.reverse.each {|line| temp_file.puts(line) }
  end
end

`mv #{TEMP_FILE} #{HISTORY_FILE}`

