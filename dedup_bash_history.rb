#!/usr/bin/env ruby

# Copyright (C) 2011 by Brian J. Adkins
#
# TIP: Add the following lines to your .bash_profile (or equiv)
#      to save the last 10000 lines
#
# export HISTCONTROL=ignoredupes:erasedups
# export HISTFILESIZE=10000
# export HISTSIZE=10000

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

history_file = File.expand_path('~/.bash_history')
backup_file = File.expand_path('~/.bash_history_backup')
temp_file = File.expand_path('~/.bash_history_temp')

`cp #{history_file} #{backup_file}`

File.open(history_file, "r") do |hfile|
  File.open(temp_file, "w") do |tfile|
    hfile.readlines.reverse.uniq.reverse.each {|line| tfile.puts(line) }
  end
end

`mv #{temp_file} #{history_file}`

