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

module DeDuper
  NUM_BACKUP_FILES = 20
  HISTORY_FILE     = File.expand_path('~/.bash_history')
  BACKUP_FILE      = File.expand_path('~/.bash_history_backup')
  TEMP_FILE        = File.expand_path('~/.bash_history_temp')

  module_function

  def rotate_backup_files n
    return if n < 1

    if File.exist?(current_file = "#{BACKUP_FILE}#{n}")
      `cp #{current_file} #{BACKUP_FILE}#{n+1}`
    end

    rotate_backup_files(n-1)
  end

  def run
    rotate_backup_files(NUM_BACKUP_FILES)
    `cp #{HISTORY_FILE} #{BACKUP_FILE}1`

    File.open(HISTORY_FILE, "r") do |hfile|
      File.open(TEMP_FILE, "w") do |tfile|
        hfile.readlines.reverse.uniq.reverse.each {|line| tfile.puts(line) }
      end
    end

    `mv #{TEMP_FILE} #{HISTORY_FILE}`
  end
end

DeDuper.run
