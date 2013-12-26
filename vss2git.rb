# = Migration tool for VSS->Git, VSS->Hg or VSS->Bzr
#
# Author::  Hanaguro
# License:: MIT License
# Version:: 1.02
#
# Copyright (c) <2012-2013>, <Satoshi Hasegawa>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted.
#
# Requirement:
#   - Windows7 or Windows XP operating system
#     Windows8 or Windows VISTA may be OK (not verified).
#
#   - Ruby 2.0 or 1.9.3 (32 bits)
#     Ruby 1.8.7 or earlier is not supported.
#
#   - Microsoft Visual Source Safe 2005 or Microsoft Visual Source Safe 6.0d
#     VSS 2005: The language setting has to be English.
#     VSS 6.0d: English version is necessary.
#
#   - Target version control system
#     The git, mercurial or bazaar has to be installed.
#     Its executable path has to be added to the PATH.
#
#
require 'win32ole'
require 'getoptlong'
require 'time'
require 'json'
require 'pp'

VERSION       = "1.02"
REVISION_DATE = "2013/12/26"
AUTHOR        = "Hanaguro"

#------------------------------------------------------------------------------
# Utility
#---------------------------------------------------------------------------*/
module Utility

  # Print header line
  # "str"
  # "------------------------------------------------------------------------"
  #
  # str:: Message
  #----------------------------------------------------------------------------
  def pps_header(str)
    str = "\n" + str + "\n" + line
    pps(str)
  end

  # Dump hash object (for debug)
  # "key                     = value"
  #
  # str:: Hash name
  # obj:: Hash object
  #----------------------------------------------------------------------------
  def pps_hash(str, obj)
    pps_header(str)

    s = ""
    obj.each do |key, value|
      s += "  #{key}".ljust(24) + "= #{value}\n"
    end
    pps(s)
  end

  # Dump object (for debug)
  #
  # str:: Object name
  # obj:: Object
  #----------------------------------------------------------------------------
  def pps_object(str, obj)
    pps_header(str)
    pp obj
  end

  # Print message to STDOUT
  #
  # str:: Message
  #----------------------------------------------------------------------------
  def pps(str)
    puts "#{str}"
  end
  private :pps

  # Seperlator line
  # "------------------------------------------------------------------------"
  #----------------------------------------------------------------------------
  def line
    "-" * 72
  end
  private :line

  # Print processing status to STDERR when verbose != 0
  # "mes1                            : mes2"
  #
  # verbose:: verbose mode
  # mes1::    1st message
  # mes2::    2nd message
  #----------------------------------------------------------------------------
  def ppe_status(verbose, mes1, mes2 = "")
    return if verbose == 0

    s =  mes1.ljust(32)
    s += ": " + mes2 unless mes2 == ""
    s += "\r"
    STDERR.print s
  end

  # Print error message and exit
  #
  # str:: Error message
  #----------------------------------------------------------------------------
  def ppe_exit(str)
    STDERR.print(str)
    exit 1
  end

  # Execute windows command
  #
  # str:: Command string
  #----------------------------------------------------------------------------
  def ex(str)
    puts str
    %x(#{str})
  end
end

#------------------------------------------------------------------------------
# MODULE: Vcs
#
# VCS (Version Control System) command module
#------------------------------------------------------------------------------
module Vcs

  #-- definition of VCS oparations
  ACTION_ADD    = "ADD"
  ACTION_BRANCH = "BRANCH"
  ACTION_COMMIT = "COMMIT"
  ACTION_INIT   = "INIT"
  ACTION_MERGE  = "MERGE"
  ACTION_MOVE   = "MOVE"
  ACTION_REMOVE = "REMOVE"
  ACTION_TAG    = "TAG"

  #-- temporally message file name
  MESSAGE_FILE  = ".message"

  #----------------------------------------------------------------------------
  # CLASS: Git
  #
  # Git command class
  #----------------------------------------------------------------------------
  class Git
    include Utility

    # Create repository
    #
    # message:: Initial commit message
    #--------------------------------------------------------------------------
    def create_repository(message)
      # create "master" branch
      ex("git init -q")

      # create .gitignore file
      ex("echo *.scc>>.gitignore")
      ex("echo #{MESSAGE_FILE}>>.gitignore")

      # initial commit
      ex("git add *")
      commit("", Time.at(0), message)
    end

    # Clean working directory
    #--------------------------------------------------------------------------
    def clean_working_directory
      ex("for /D %a in (*) do @if not %a==.git rd %a /s /q")
      ex("for %a in (*) do @if not %a==.gitignore del %a /f")
    end

    # Create branch and switch to the branch
    #
    # branch::      Branch name
    # base_branch:: Base branch name
    #--------------------------------------------------------------------------
    def create_branch(branch, base_branch)
      switch_branch(base_branch)
      ex("git branch -q #{branch}")
      switch_branch(branch)
    end

    # Switch branch
    #
    # branch:: Branch name
    #--------------------------------------------------------------------------
    def switch_branch(branch)
      ex("git checkout -q #{branch}")
    end

    # Add file to index
    #
    # file:: File name
    #--------------------------------------------------------------------------
    def add(file = ".")
      ex("git add \"#{file}\"")
    end

    # Merge specified branch to current branch
    #
    # branch::  Branch name which you want to merge
    # author::  Author
    # date::    Date
    # message:: Message
    #--------------------------------------------------------------------------
    def merge(branch, author, date, message)
      ex("git merge --no-ff --no-commit -q #{branch} 2>&1 >NUL")
      commit(author, date, message)
    end

    # Commit file
    #
    # author::  Author
    # date::    Date
    # message:: Message
    # file::    File name. The "" means all files.
    #--------------------------------------------------------------------------
    def commit(author, date, message, file = "")
      # Create message file (temporally)
      message      = "-" if message == ""
      message_file = MESSAGE_FILE

      ec = Encoding::Converter.new(Encoding.find("locale"), "utf-8")

      File.open(message_file, "w") do |f|
        begin
          f.print(ec.convert(message))
        rescue
          f.print("")
        end
      end

      # Commit
      cmd =  "git commit -q"
      cmd << " --file=#{message_file}"
      cmd << " --author=\"#{author}\"" unless author == ""
      cmd << " --date=\"#{date}\"" unless date == ""
      cmd << " \"#{file}\"" unless file == ""
      ex(cmd)

      ex("del #{message_file}")
    end

    # Assign tag
    #
    # tag:: Tag name
    # author:: Author
    # date::   Date
    #--------------------------------------------------------------------------
    def tag(tag, author, date)
      ex("git tag -f \"#{tag}\"")
    end

    # Verify repository
    #--------------------------------------------------------------------------
    def verify
      ex("git verify")
    end

    # Pack repository
    #--------------------------------------------------------------------------
    def pack
      ex("git gc")
    end

    # Get latest commit information
    #--------------------------------------------------------------------------
    def latest_commit
      log = ex("git log -n 1")

      ec = Encoding::Converter.new("utf-8", Encoding.find("locale"))

      ret = {}
      ret[:Commit] = ec.convert(log).scan(/^commit *(.*)$/)[0][0]
      ret[:Date]   = Time.parse(ec.convert(log).scan(/^Date: *(.*)$/)[0][0])
      ret[:Author] = ec.convert(log).scan(/^Author: *(.*)$/)[0][0]

      ret
    end
  end # Class Git

  #----------------------------------------------------------------------------
  # CLASS: Hg
  #
  # Hg command class
  # (Not verified sufficiently)
  #----------------------------------------------------------------------------
  class Hg
    include Utility

    # Create repository
    #
    # message:: Initial commit message
    #--------------------------------------------------------------------------
    def create_repository(message)
      # create "master" branch
      ex("hg init")
      ex("hg branch master")

      # create .hgignore file
      ex("echo syntax: glob>>.hgignore")
      ex("echo *.scc>>.hgignore")
      ex("echo #{MESSAGE_FILE}>>.hgignore")

      # initial commit
      ex("hg add *")
      commit("", Time.at(0), message)
    end

    # Clean working directory
    #--------------------------------------------------------------------------
    def clean_working_directory
      ex("for /D %a in (*) do @if not %a==.hg rd %a /s /q")
      ex("for %a in (*) do @if not %a==.hgignore del %a /f")
    end

    # Create branch and switch to the branch
    #
    # branch::      Branch name
    # base_branch:: Base branch name
    #--------------------------------------------------------------------------
    def create_branch(branch, base_branch)
      switch_branch(base_branch)
      ex("hg branch #{branch}")
      commit("", Time.at(0), "create branch")
    end

    # Switch branch
    #
    # branch:: Branch name
    #--------------------------------------------------------------------------
    def switch_branch(branch)
      ex("hg update -C #{branch}")
    end

    # Add file to index
    #
    # file:: File name
    #--------------------------------------------------------------------------
    def add(file = ".")
      ex("hg add \"#{file}\"")
    end

    # Merge specified branch to current branch
    #
    # branch::  Branch name which you want to merge
    # author::  Author
    # date::    Date
    # message:: Message
    #--------------------------------------------------------------------------
    def merge(branch, author, date, message)
      ex("hg merge #{branch}")
      commit(author, date, message)
    end

    # Commit the file
    #
    # author::  Author
    # date::    Date
    # message:: Message
    # file::    File name. The "" means all files.
    #--------------------------------------------------------------------------
    def commit(author, date, message, file = "")
      # Create message file (temporally)
      message      = "-" if message == ""
      message_file = MESSAGE_FILE

      File.open(message_file, "w") do |f|
        begin
          f.print(message)
        rescue
          f.print("")
        end
      end

      # Commit
      cmd =  "hg commit"
      cmd << " --logfile #{message_file}"
      cmd << " --user \"#{author}\"" unless author == ""
      cmd << " --date \"#{date}\"" unless date == ""
      cmd << " \"#{file}\"" unless file == ""
      ex(cmd)

      ex("del #{message_file}")
    end

    # Assign tag
    #
    # tag::    Tag name
    # author:: Author
    # date::   Date
    #--------------------------------------------------------------------------
    def tag(tag, author, date)
      cmd =  "hg tag -f"
      cmd << " --user \"#{author}\"" unless author == ""
      cmd << " --date \"#{date}\"" unless date == ""
      cmd << " \"#{tag}\""
      ex(cmd)
    end

    # Verify repository
    #--------------------------------------------------------------------------
    def verify
      ex("hg verify")
    end

    # Pack repository
    #--------------------------------------------------------------------------
    def pack
    end

    # Get latest commit information
    #--------------------------------------------------------------------------
    def latest_commit
      log = ex("hg log -l 1")

      ret = {}
      ret[:Commit] = log.scan(/^changeset: *(.*)$/)[0][0]
      ret[:Date]   = Time.parse(log.scan(/^date: *(.*)$/)[0][0])
      ret[:Author] = log.scan(/^user: *(.*)$/)[0][0]

      ret
    end
  end # Class Hg

  #----------------------------------------------------------------------------
  # CLASS: Bzr
  #
  # Bazaar command class
  # (Not verified sufficiently)
  #----------------------------------------------------------------------------
  class Bzr
    include Utility

    # Initialize instance
    #--------------------------------------------------------------------------
    def initialize
      @basedir = Dir.pwd
    end

    # Create repository
    #
    # message:: Initial commit message
    #--------------------------------------------------------------------------
    def create_repository(message)
      # create "master" branch
      ex("bzr init-repo .")
      ex("bzr config add.maximum_file_size=50000000")
      ex("md master")
      switch_branch("master")
      ex("bzr init")

      # create .gitignore file
      ex("bzr ignore *.scc")

      # initial commit
      ex("bzr add *")
      commit("", Time.at(0), message)
    end

    # Clean working directory
    #--------------------------------------------------------------------------
    def clean_working_directory
      ex("for /D %a in (*) do @if not %a==.bzr rd %a /s /q")
      ex("for %a in (*) do @if not %a==.bzrignore del %a /f")
    end

    # Create branch and switch to the branch
    #
    # branch::      Branch name
    # base_branch:: Base branch name
    #--------------------------------------------------------------------------
    def create_branch(branch, base_branch)
      switch_branch(@basedir)
      ex("bzr branch #{base_branch} #{branch}")
      switch_branch(branch)
    end

    # Switch branch
    #
    # branch:: Branch name
    #--------------------------------------------------------------------------
    def switch_branch(branch)
      Dir.chdir(@basedir)
      Dir.chdir(branch)
    end

    # Add file to index
    #
    # file:: File name
    #--------------------------------------------------------------------------
    def add(file = "")
      cmd =  "bzr add"
      cmd << " \"#{file}\"" unless file == ""
      ex(cmd)
    end

    # Merge specified branch to current branch
    #
    # branch::  Branch name which you want to merge
    # author::  Author
    # date::    Date
    # message:: Message
    #--------------------------------------------------------------------------
    def merge(branch, author, date, message)
      ex("bzr merge ..\\#{branch}")
      commit(author, date, message)
    end

    # Commit the file
    #
    # author::  Author
    # date::    Date
    # message:: Message
    # file::    File name. The "" means all files.
    #--------------------------------------------------------------------------
    def commit(author, date, message, file = "")
      # Create message file (temporally)
      message      = "-" if message == ""
      message_file = "..\\#{MESSAGE_FILE}"

      File.open(message_file, "w") do |f|
        begin
          f.print(message)
        rescue
          ppe_exit "ERROR: Bzr.commit: Cannot open file: #{message_file}"
        end
      end

      # Commit
      cmd =  "bzr commit -q"
      cmd << " --file=#{message_file}"
      cmd << " --author=\"#{author}\"" unless author == ""
      cmd << " --commit-time=\"#{date}\"" unless date == ""
      cmd << " \"#{file}\"" unless file == ""
      ex(cmd)

      ex("del #{message_file}")
    end

    # Assign tag
    #
    # tag::    Tag name
    # author:: Author
    # date::   Date
    #--------------------------------------------------------------------------
    def tag(tag, author, date)
      ex("bzr tag --force \"#{tag}\"")
    end

    # Verify repository
    #--------------------------------------------------------------------------
    def verify
      ex("bzr check")
    end

    # Pack repository
    #--------------------------------------------------------------------------
    def pack
      ex("bzr pack")
    end

    # Get latest commit information
    #--------------------------------------------------------------------------
    def latest_commit
      log = ex("bzr log -r-1")

      ret = {}
      ret[:Commit] = log.scan(/^revno: *(.*)$/)[0][0]
      ret[:Date]   = Time.parse(log.scan(/^timestamp: *(.*)$/)[0][0])
      ret[:Author] = log.scan(/^author: *(.*)$/)[0][0]

      ret
    end
  end # Class Bzr
end # Module Vcs

#------------------------------------------------------------------------------
# CLASS: Vss
#
# VSS (Visual Source Safe) operation class
#
# This class operates Visual Source Safe via Win32OLE interface.
#------------------------------------------------------------------------------
class VssError < StandardError; end

class Vss
  include Utility

  # VSS constant
  module VssConstant
  end

  #-- definition of VCS oparations
  ACTION_ADD    = "ADD"
  ACTION_BRANCH = "BRANCH"
  ACTION_COMMIT = "COMMIT"
  ACTION_INIT   = "INIT"
  ACTION_MERGE  = "MERGE"
  ACTION_MOVE   = "MOVE"
  ACTION_REMOVE = "REMOVE"
  ACTION_TAG    = "TAG"

  # VSS actions
  VSS_ACTION = [
    { VssAction: /added/,                Sym: :Added,              Action: nil        },
    { VssAction: /archived versions of/, Sym: :ArchivedVersionsOf, Action: ACTION_ADD },
    { VssAction: /archived/,             Sym: :Archived,           Action: nil        },
    { VssAction: /branched at version/,  Sym: :BranchedAtVersion,  Action: nil        },
    { VssAction: /checked in/,           Sym: :CheckedIn,          Action: ACTION_ADD },
    { VssAction: /created/,              Sym: :Created,            Action: ACTION_ADD },
    { VssAction: /deleted/,              Sym: :Deleted,            Action: nil        },
    { VssAction: /destroyed/,            Sym: :Destroyed,          Action: nil        },
    { VssAction: /labeled/,              Sym: :Labeled,            Action: ACTION_TAG },
    { VssAction: /moved from/,           Sym: :MovedFrom,          Action: nil        },
    { VssAction: /moved to/,             Sym: :MovedTo,            Action: nil        },
    { VssAction: /pinned to version/,    Sym: :PinnedToVersion,    Action: nil        },
    { VssAction: /purged/,               Sym: :Purged,             Action: nil        },
    { VssAction: /recovered/,            Sym: :Recovered,          Action: nil        },
    { VssAction: /renamed to/,           Sym: :RenamedTo,          Action: nil        },
    { VssAction: /restored/,             Sym: :Restored,           Action: nil        },
    { VssAction: /rollback to version/,  Sym: :RollbackToVersion,  Action: nil        },
    { VssAction: /shared/,               Sym: :Shared,             Action: nil        },
    { VssAction: /unpinned/,             Sym: :Unpinned,           Action: nil        },
    { VssAction: /.*/,                   Sym: :Other,              Action: "OTHER"    }]

  # Initialize instance
  #
  # vssdir::   VSS database directory
  # user::     VSS user name
  # password:: VSS pasword
  # project::  Project name
  # workdir::  Working directory
  # verbose::  Verbose mode
  #--------------------------------------------------------------------------
  def initialize(vssdir, user, password, project, workingdir, verbose)
    @project    = project
    @workingdir = workingdir
    @verbose    = verbose

    # open VSS db
    begin
      @vssdb = WIN32OLE.new("SourceSafe")
      WIN32OLE.const_load(@vssdb, VssConstant)
    rescue
      raise VssError,
        %(\nERROR: Visual Source Safe is not installed.)
    end

    # validation of srcsafe.ini
    file = vssdir + "srcsafe.ini"
    unless FileTest.exist?(file)
      raise VssError,
        %(\nERROR: Invalid VSS database folder: #{file})
    end

    begin
      @vssdb.Open(file, user, password)
    rescue
      raise VssError,
        %(\nERROR: Invalid user name or password)
    end

    if @vssdb.GetSetting("Force_Dir") == "Yes"
      raise VssError,
        %(\nERROR: VSS setting error.) +
        %(\n  "Assume working folder based on current project" should be off.) +
        %(\n  "Tools" -> "Options" -> "Command Line Options" tab)
    end

    if @vssdb.GetSetting("Force_Prj") == "Yes"
      raise VssError,
        %(\nERROR: VSS setting error.) +
        %(\n  "Assume project based on working folder" should be off.) +
        %(\n  "Tools" -> "Options" -> "Command Line Options" tab)
    end
  end

  # Get history
  #----------------------------------------------------------------------------
  def get_history
    history  = []
    @counter = { File: 0 }
    @vssinfo = {}
    VSS_ACTION.each do |act|
      @vssinfo[act[:Sym]] = 0
    end

    files = get_filelist(@project)

    files.each_with_index do |file, i|
      item = get_item(file)
      next unless item

      history += get_history_of_the_file(file, item)
      ppe_status(
        @verbose,
        "Get history ...",
        "#{i + 1} / #{files.size} files")
    end

    ppe_status(@verbose, "\n")
    pps_object("history generated by get_history", history) if @verbose >= 3

    [history, @vssinfo]
  end

  # Get file list
  #
  # project:: project folder name (Ex. $/, $/project etc.)
  #----------------------------------------------------------------------------
  def get_filelist(project)
    files = walk_tree(project).uniq.sort
    ppe_status(@verbose, "Make file list ...", "#{files.size} files\n")
    files
  end
  private :get_filelist

  # Walk VSS project tree to get file list
  #
  # project:: project folder name (Ex. $/, $/project etc.)
  #----------------------------------------------------------------------------
  def walk_tree(project)
    files = []

    root = get_item(project)
    return files unless root

    items = root.Items(false)

    items.each do |item|
      pps_item(item)

      if item.Type == VssConstant::VSSITEM_PROJECT
        subproject = item.Name
        files += walk_tree("#{project}#{subproject}/")
        ppe_status(
          @verbose, "Meke file list ...", "#{@counter[:File]} files")
      else
        @counter[:File] += 1
        files << item.Spec
      end
    end

    files
  end
  private :walk_tree

  # Get IVSSItem object
  #
  # file:: file name or project folder name
  #----------------------------------------------------------------------------
  def get_item(file)
    begin
      @vssdb.VSSItem(file, false)
    rescue
      message = "WARNING: Cannot handle the file: #{file}"
      puts message
      ppe_status(@verbose, message + "\n")
      nil
    end
  end
  private :get_item

  # Get history of the file
  #
  # file:: file name
  # item:: VSSItem object
  #----------------------------------------------------------------------------
  def get_history_of_the_file(file, item)
    history = []

    versions = item.Versions

    versions.each do |ver|
      pps_version(file, ver)

      hs = {}
      hs[:File]          = file
      hs[:Version]       = ver.VersionNumber
      hs[:Author]        = ver.Username.downcase
      hs[:Date]          = ver.Date
      hs[:Message]       = ver.Comment.gsub(/[\r\n][\r\n]/, "\n").chomp
      hs[:Tag]           = ver.Label.chomp
      hs[:LatestVersion] = (item.VersionNumber == hs[:Version])

      pps ver.Action if @verbose >= 3

      action = VSS_ACTION.find do |act|
        ver.Action.downcase =~ act[:VssAction]
      end

      @vssinfo[action[:Sym]] += 1

      case action[:Action]
      when "OTHER"
        raise VssError,
          %(\nERROR: Unexpected operation: #{ver.Action.downcase})
      when nil
        next
      else
        hs[:Action] = action[:Action]
      end

      history << hs
    end
    history
  end
  private :get_history_of_the_file

  # Get file
  #
  # file::    File name or project folder name
  # version:: Version number.
  #           If version is nil, the latest version of file is got.
  #----------------------------------------------------------------------------
  def get_file(file, version)
    item = get_item(file)
    return unless item

    item = item.Version(version) if version
    fail "item.Version() return nil" unless item

    # VSSFLAG setting
    flag = VssConstant::VSSFLAG_CMPFAIL |
      VssConstant::VSSFLAG_FORCEDIRNO |
      VssConstant::VSSFLAG_RECURSYES |
      VssConstant::VSSFLAG_REPREPLACE

    # build local path name
    lpath = file.gsub(/[^\/]*$/, "").gsub(@project, "")
    lpath = @workingdir + lpath.gsub(/\//, "\\")
    lpath.gsub!(/\\$/, "")

    case item.Type
    when VssConstant::VSSITEM_PROJECT
      lpath = ".\\" + lpath
      ex("if not exist #{lpath} md #{lpath}")
    when VssConstant::VSSITEM_FILE
      lpath = ".\\" + lpath + "\\" + item.Name
    end

    # get file
    puts "Checkout #{file}"
    begin
      item.Get(lpath, flag)
      true
    rescue
      puts "WARNING: Cannot get file: #{file}: V#{version}"
      false
    end
  end

  # Dump IVSSItem object (for debug)
  #
  # item:: IVSSItem object
  #----------------------------------------------------------------------------
  def pps_item(item)
    return unless @verbose >= 3

    pps_header("item")
    puts "item.Spec: #{item.Spec}"
    puts "item.Deleted: #{item.Deleted}"
    puts "item.Type: #{item.Type}"
    puts "item.LocalSpec: #{item.LocalSpec}"
    puts "item.Name: #{item.Name}"
    puts "item.VersionNumber: #{item.VersionNumber}"
  end
  private :pps_item

  # Dump IVSSVersion object (for debug)
  #
  # file:: File name
  # ver::  IVSSVersion object
  #----------------------------------------------------------------------------
  def pps_version(file, ver)
    return unless @verbose >= 3

    pps_header("version")
    puts "file: #{file}"
    puts "ver.VersionNumber: #{ver.VersionNumber}"
    puts "ver.Action: #{ver.Action}"
    puts "ver.Date: #{ver.Date}"
    puts "ver.Username: #{ver.Username}"
    puts "ver.Comment: #{ver.Comment}"
    puts "ver.Label: #{ver.Label}"
  end
  private :pps_version
end # Class Vss

#------------------------------------------------------------------------------
# CLASS: Vss2xxx
#
# Migrate from VSS to Git, Hg or Bzr
#------------------------------------------------------------------------------
class Vss2xxx
  include Vcs
  include Utility

  MASTER_BRANCH  = "master"
  PRODUCT_BRANCH = "product"
  DEVELOP_BRANCH = "develop"

  #-- Each commit in the following time range are assumed to a same changeset.
  VSS_CHANGESET_RANGE_1 = 600 # sec # When same author & same message
  VSS_CHANGESET_RANGE_2 = 120 # sec # When same author & no message

  # Initialize instance
  #
  # opt:: command line option
  # [:Vssdir] VSS repository folder
  # [:User] VSS user account
  # [:Password] VSS password
  # [:Project] VSS project foler
  # [:Vcs] Target VCS ("git", "hg" or "bzr")
  # [:Emaildomain] E-mail domain address.
  # [:Branch] Branching model
  # [:Verbose] Debug mode
  # [:Update] Update mode
  # [:Timeshift] Time shift value when migrating
  # [:Workingdir] Working folder
  # [:Version] Version number of this script
  #----------------------------------------------------------------------------
  def initialize(opt)
    @vssdir       = opt[:Vssdir]
    @user         = opt[:User]
    @password     = opt[:Password]
    @project      = opt[:Project]
    @vcs          = opt[:Vcs]
    @emaildomain  = opt[:Emaildomain]
    @userlistfile = opt[:Userlist]
    @userlist     = nil
    @branch       = opt[:Branch]
    @verbose      = opt[:Verbose]
    @update       = opt[:Update]
    @timeshift    = opt[:Timeshift]
    @workingdir   = opt[:Workingdir]
    @version      = opt[:Version]

    # check mandatory options
    ppe_exit "ERROR: No option: -s, --vssdir" unless @vssdir
    ppe_exit "ERROR: No option: -u, --user"   unless @user
    ppe_exit "ERROR: No option: -c, --vcs"    unless @vcs

    # check @vssdir
    @vssdir += "\\" unless @vssdir[-1] == "\\"

    # check @project
    if @project == ""
      @project = "$/"
    elsif @project !~ /^\$\/.*/ ||
          @project.include?("\\")
      ppe_exit "ERROR: Invalid VSS_PROJECT_PATH: #{@project}"
    elsif @project[-1] != "/"
      @project += "/"
    end

    # check @workingdir
    if @workingdir == ""
    elsif @workingdir.include?("/")
      ppe_exit "ERROR: Invalid option --workingdir #{@workingdir}"
    elsif @workingdir[-1] != "\\"
      @workingdir += "\\"
    end

    # check @vcs
    unless @vcs == "git" || @vcs == "bzr" || @vcs == "hg"
      ppe_exit "ERROR: Invalid option: --vcs #{@vcs}"
    end

    # @emaildomain
    @emaildomain ||= "localhost"

    # @userlist
    if @userlistfile
      unless File.exist?(@userlistfile)
        ppe_exit "ERROR: File does not exist: (#{@userlistfile})"
      end
      File.open(@userlistfile, "r") do |file|
        @userlist = JSON.load(file)
      end
    end

    # check @branch
    unless 0 <= @branch && @branch <= 2
      ppe_exit "ERROR: Invalid option: --branch #{@branch}"
    end

    # check @verbose
    unless 0 <= @verbose && @verbose <= 3
      ppe_exit "ERROR: Invalid option: --verbose #{@verbose}"
    end

    # check @timeshift
    unless -12 <= @timeshift && @timeshift <= 12
      ppe_exit "ERROR: Invalid option: --timeshift #{@timeshift}"
    end

    case @branch
    when 0
      @product_branch = MASTER_BRANCH
      @develop_branch = MASTER_BRANCH
    when 1
      @product_branch = MASTER_BRANCH
      @develop_branch = DEVELOP_BRANCH
    when 2
      @product_branch = PRODUCT_BRANCH
      @develop_branch = MASTER_BRANCH
    end

    @counter = {}
    @counter[:History]   = 0
    @counter[:Changeset] = 0

    @vss = Vss.new(@vssdir, @user, @password, @project, @workingdir, @verbose)
  end

  # Start migration
  #----------------------------------------------------------------------------
  def run

    if !@update
      # current folder must be empty
      ppe_exit "ERROR: Git repository exists." if File.exists?(".git")
      ppe_exit "ERROR: Current folder must be empty." if Dir.glob("*").size > 0
    else
      repodir =
      case @vcs
      when 'git'
        ".git"
      when 'hg'
        ".hg"
      when 'bzr'
        ".bzr"
      end

      unless File.exist?(repodir)
        ppe_exit "ERROR: no local repository #{repodir}"
      end
    end

    # get history from VSS
    history, vssinfo = @vss.get_history
    history          = modify_author(history)
    history          = modify_time(history, @timeshift)
    changesets       = make_changeset(history)

    # print log
    pps_title
    pps_hash("VSS information", vssinfo)

    migrate(changesets)
  end

  # Modify author in the history
  #
  # history:: All history getting from VSS
  #----------------------------------------------------------------------------
  def modify_author(history)
    userlist = @userlist || {}

    # Modify Author ("aaaaa" => "bbbbb <ccccc@ddd.eee>" )
    out = history.map do |hs|

      author = hs[:Author]

      if userlist[author]
        name, email      = userlist[author]
      else
        name             = author
        email            = "#{author}@#{@emaildomain}"
        userlist[author] = [name, email]
      end

      hs[:Author] = "#{name} <#{email}>"
      hs
    end

    puts JSON.pretty_generate(userlist) if @verbose >= 2
    out
  end

  # Modify time in the history
  #
  # history:: All history getting from VSS
  # timeshift:: Time to shift
  #----------------------------------------------------------------------------
  def modify_time(history, timeshift)
    out = history.map do |hs|
      hs[:Date] += (timeshift * 60 * 60)
      hs
    end
    out
  end

  # Make chageset
  #
  # history:: All history getting from VSS
  #----------------------------------------------------------------------------
  def make_changeset(history)
    changesets = []

    # Sort by [date -> author -> message]
    history.sort_by! do |hs|
      hs[:Date].to_s + hs[:Author] + hs[:Message] + hs[:File]
    end

    # Combine near commits
    cs             = [history[0]]
    last           = {}
    last[:Author]  = history[0][:Author]
    last[:Message] = history[0][:Message]
    last[:Date]    = history[0][:Date]

    tag = {}

    history.each_with_index do |hs, i|

      @counter[:History] += 1
      ppe_status(
        @verbose,
        "Make changeset ...",
        "#{@counter[:History]} / #{history.size} histories")

      next if i == 0

      same_changeset =
        case hs[:Action]
        when Vcs::ACTION_TAG
          # Tag operation is rgarded as one change set
          # Skip duplicate tag
          next if tag[hs[:Tag]]
          tag[hs[:Tag]] = true
          false
        else
          # When same author and same massage, these operation within
          # VSS_CHANGESET_RANGE_1 are regarded as same change set.
          # When same author and no massage, these operation within
          # VSS_CHANGESET_RANGE_2 are regarded as same change set.
          if last[:Author] == hs[:Author] && last[:Message] == hs[:Message]
            if hs[:Message] != ""
              (hs[:Date] - last[:Date] <= VSS_CHANGESET_RANGE_1)
            else
              (hs[:Date] - last[:Date] <= VSS_CHANGESET_RANGE_2)
            end
          else
            false
          end
        end

      if same_changeset
        cs << hs
      else
        changesets << cs

        cs             = [hs]
        last[:Author]  = hs[:Author]
        last[:Message] = hs[:Message]
      end
      last[:Date] = hs[:Date]
    end
    ppe_status(@verbose, "\n")

    # output last changeset
    changesets << cs

    pps_object("operations by make_changeset", changesets) if @verbose >= 3

    changesets
  end
  private :make_changeset

  # Start migration
  #
  # changesets:: changesets
  #----------------------------------------------------------------------------
  def migrate(changesets)
    vcs =
      case @vcs
      when "bzr"
        Bzr.new
      when "git"
        Git.new
      when "hg"
        Hg.new
      else
        nil
      end

    pps_header("Start migration")
    unless @update
      vcs.create_repository("vss2xxx: Version #{VERSION}")
      case @branch
      when 1
        vcs.create_branch(@develop_branch, @product_branch)
      when 2
        vcs.create_branch(@product_branch, @develop_branch)
      end
    end

    vcs.switch_branch(@develop_branch)

    last_date = vcs.latest_commit[:Date] if @update

    changesets.each do |cs|

      # If the VSS is updated within VSS_CHANGESET_RANGE_1, skip update
      if @update
        time_last_commit = changesets[-1][-1][:Date]

        if VSS_CHANGESET_RANGE_1 >= Time.now - time_last_commit
          ppe_status(
            @verbose,
            "Skip update ...",
            "The VSS has been updated within #{VSS_CHANGESET_RANGE_1} sec")
          break
        end
      end

      # get recent update
      next if @update && cs[0][:Date] <= last_date

      @counter[:Changeset] += 1

      pps_header(
        "No. #{@counter[:Changeset]} / #{changesets.size} " +
        "(#{cs[0][:Date]} / #{cs[0][:Author]})")

      counter = {}
      counter[:Ng] = 0
      counter[:Ok] = 0

      cs.each do |op|
        case op[:Action]
        when Vcs::ACTION_ADD
          # When you like to get latest version of file,
          # you have to specify nil to version for Vss::get_file()
          version = op[:LatestVersion] ? nil : op[:Version]

          counter[:Ok] += 1 if @vss.get_file(op[:File], version)
        end

        ppe_status(
          @verbose,
          "Changeset #{@counter[:Changeset]} / #{changesets.size}",
          "Get #{counter[:Ok]} files")
      end

      op = cs[-1]	# latest file in a change set

      case op[:Action]
      when Vcs::ACTION_ADD
        author  = op[:Author]
        date    = op[:Date]
        message = op[:Message]

        vcs.add
        vcs.commit(author, date, message)

        ppe_status(
          @verbose,
          "Changeset #{@counter[:Changeset]} / #{changesets.size}",
          "Commit #{counter[:Ok]} files")
      when Vcs::ACTION_TAG
        author  = op[:Author]
        date    = op[:Date]
        tag     = op[:Tag]

        # Only ASCII characters are allowed for tag
        if tag.ascii_only?

          # merge develop branch to product branch
          if @branch > 0
            vcs.switch_branch(@product_branch)
            vcs.merge(@develop_branch, author, date, ".")
          end

          # Tag
          ppe_status(
            @verbose,
            "Changeset #{@counter[:Changeset]} / #{changesets.size}",
            "Tag: #{tag}".ljust(20))
            vcs.tag(tag, author, date)

          # return to develop branch
          vcs.switch_branch(@develop_branch) if @branch > 0

        else
          puts "WARNING: Illegal tag: #{tag}"
        end
      end
      ppe_status(@verbose, "\n")
    end
    ppe_status(@verbose, "\n")

    # finalize
    commit_latest_files(vcs) unless @update

    # pack repository
    ppe_status(@verbose, "Pack repository ...\n")
    vcs.pack
  end
  private :migrate

  # Get and commit latest files
  # 1. Clean working directory
  # 2. Get latest files from VSS
  # 3. Commit
  #----------------------------------------------------------------------------
  def commit_latest_files(vcs)
    pps_header("Latest files")

    # Clean working directory
    vcs.switch_branch(@develop_branch)
    vcs.clean_working_directory
    ppe_status(@verbose, "Clean working directory ...\n")

    # Following sleep is necessary.
    # Without this, a file permision error happens when executing get_file()
    # I don't know why ....
    sleep(2)

    # Get latest version
    ppe_status(@verbose, "Get latest files ...\n")
    @vss.get_file(@project, nil)

    # Commit
    ppe_status(@verbose, "Commit ...\n")
    vcs.add
    vcs.commit("", "", "vss2xxx")
  end
  private :commit_latest_files

  # Print vss2xxx execution information
  #----------------------------------------------------------------------------
  def pps_title
    pps_header("Command information")
    pps "  Date              ".ljust(24) + "= #{Time.now}"
    pps "  vss2xxx Version   ".ljust(24) + "= #{@version}"
    pps "  Vss folder        ".ljust(24) + "= #{@vssdir}"
    pps "  Vss user          ".ljust(24) + "= #{@user}"
    pps "  Vss root project  ".ljust(24) + "= #{@project}"
    pps "  Migrate to        ".ljust(24) + "= #{@vcs}"
    pps "  E-mail domain     ".ljust(24) + "= #{@emaildomain}"
    pps "  User list file    ".ljust(24) + "= #{@userlistfile}"
    pps "  Branching model   ".ljust(24) + "= #{@branch}"
    pps "  Verbose mode      ".ljust(24) + "= #{@verbose}"
    pps "  Update mode       ".ljust(24) + "= #{@update}"
    pps "  Time shift value  ".ljust(24) + "= #{@timeshift}"
    pps "  Working directory ".ljust(24) + "= #{@workingdir}"
  end
  private :pps_title
end

#------------------------------------------------------------------------------
# Application class
#------------------------------------------------------------------------------
class App
  include Utility

  def version
    puts "Version: #{VERSION}"
    puts "Date:    #{REVISION_DATE}"
    puts "Author:  #{AUTHOR}"
  end

  def initialize
    @opt = {}
    @opt[:Vssdir]      = nil
    @opt[:User]        = nil
    @opt[:Password]    = nil
    @opt[:Project]     = nil
    @opt[:Vcs]         = nil
    @opt[:Emaildomain] = nil
    @opt[:Userlist]    = nil
    @opt[:Branch]      = 0
    @opt[:Verbose]     = 1
    @opt[:Update]      = false
    @opt[:Timeshift]   = 0     # local time = 0
    @opt[:Workingdir]  = ""
    @opt[:Version]     = VERSION

    ppe_exit(usage) if 0 == ARGV.size

    get_options
  end

  def usage
  <<-USAGE
Usage: #{File.basename $PROGRAM_NAME} -s <vssdir> -u <user> [-p <password>] -c <vcs>
                    [-d <email domain>] [-l <user list>]
                    [-b <branch>] [-e <verbose>] [-t <time>]
                    [-w <workingdir>] [-r] VSS_PROJECT

    -s|--vssdir       Absolute path to VSS repository
    -u|--user         VSS user name
    -p|--password     VSS password
    -c|--vcs          Target version control system
                      "git", "hg" or "bzr"
    -d|--emaildomain  e-mail domain
    -l|--userlist     User list file (JSON format)
                        Ex.
                        {
                          "user name on VSS":
                           ["user name on VCS", "e-mail address"],
                          "user name on VSS":
                           ["user name on VCS", "e-mail address"],
                          ...
                        }
    -b|--branch       A successful Git branching model (0, 1, 2) (default:0)
                        0: No branching model
                        1: Branching model type 1
                           master:  Production branch
                           develop: Development branch
                        2: Branching model type 2
                           master:  Development branch
                           product: Production branch
    -e|--verbose      Verbose mode (0, 1, 2, 3) (default:1)
                        STDOUT
                          0-1: Output migration log
                          2:   + author list
                          3:   + dump of internal objest (for debug)
                        STDERR
                          0:   No output
                          1-3: Processing status
    -t|--timeshift    Time to shift (-12 .. 12)
    -w|--workingdir   Path to the root of working folder
    -r|--update       Update mode
    -v|--version      Print version
    -h|--help         Print help
     USAGE
  end

  def get_options
    opts = GetoptLong.new(
      ["--vssdir", "-s", GetoptLong::REQUIRED_ARGUMENT],
      ["--user", "-u", GetoptLong::REQUIRED_ARGUMENT],
      ["--password", "-p", GetoptLong::REQUIRED_ARGUMENT],
      ["--vcs", "-c", GetoptLong::REQUIRED_ARGUMENT],
      ["--emaildomain", "-d", GetoptLong::REQUIRED_ARGUMENT],
      ["--userlist", "-l", GetoptLong::REQUIRED_ARGUMENT],
      ["--branch", "-b", GetoptLong::REQUIRED_ARGUMENT],
      ["--verbose", "-e", GetoptLong::REQUIRED_ARGUMENT],
      ["--update", "-r", GetoptLong::NO_ARGUMENT],
      ["--timeshift", "-t", GetoptLong::REQUIRED_ARGUMENT],
      ["--workingdir", "-w", GetoptLong::REQUIRED_ARGUMENT],
      ["--version", "-v", GetoptLong::NO_ARGUMENT],
      ["--help", "-h", GetoptLong::NO_ARGUMENT]
    )
    opts.each do |opt, arg|
      case opt
      when "--vssdir"
        @opt[:Vssdir]      = arg
      when "--user"
        @opt[:User]        = arg
      when "--password"
        @opt[:Password]    = arg
      when "--vcs"
        @opt[:Vcs]         = arg.downcase
      when "--emaildomain"
        @opt[:Emaildomain] = arg
      when "--userlist"
        @opt[:Userlist]    = arg
      when "--branch"
        @opt[:Branch]      = arg.to_i
      when "--verbose"
        @opt[:Verbose]     = arg.to_i
      when "--update"
        @opt[:Update]      = true
      when "--timeshift"
        @opt[:Timeshift]   = arg.to_i
      when "--workingdir"
        @opt[:Workingdir]  = arg
      when "--version"
        version
        exit 0
      when "--help"
        puts usage
        exit 0
      else
        ppe_exit "ERROR: Invalid option: #{opt} = #{arg}"
      end
    end

    if ARGV.size != 1
      STDERR.print usage + "\n"
      ppe_exit "ERROR: VSS_PROJECT_PATH is not specified"
    end
    @opt[:Project] = ARGV[0]
  end

  def run
    vss2xxx = Vss2xxx.new(@opt)
    vss2xxx.run
  end
end

App.new.run
