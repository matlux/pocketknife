class Pocketknife
  # == Node
  #
  # A node represents a remote computer that will be managed with Pocketknife and <tt>chef-solo</tt>. It can connect to a node, execute commands on it, install the stack, and upload and apply configurations to it.
  class Node
    # String name of the node.
    attr_accessor :name

    # Instance of a {Pocketknife}.
    attr_accessor :pocketknife

    # Instance of Rye::Box connection, cached by {#connection}.
    attr_accessor :connection_cache

    # Hash with information about platform, cached by {#platform}.
    attr_accessor :platform_cache
    
    @sudo = ""

    # Initialize a new node.
    #
    # @param [String] name A node name.
    # @param [Pocketknife] pocketknife
    def initialize(name, pocketknife)
      self.name = name
      self.pocketknife = pocketknife
      if pocketknife.sudoName
         @sudo = "sudo -u #{pocketknife.sudoName} "
      end   
      if pocketknife.sudoName == "root"
         @sudo = "sudo "
      end   
      self.connection_cache = nil
      @user = self.pocketknife.user
      @working_dir = Pathname.new("/tmp/chefwork")
      
      puts "@working_dir=#{@working_dir}"
          # Remote path to Chef's settings
    # @private
    @ETC_CHEF = @working_dir + "etc/chef"
    # Remote path to solo.rb
    # @private
    @SOLO_RB = @ETC_CHEF + "solo.rb"
    # Remote path to node.json
    # @private
    @NODE_JSON = @ETC_CHEF + "node.json"
    # Remote path to pocketknife's deployed configuration
    # @private
    @VAR_POCKETKNIFE = @working_dir + "var/local/pocketknife"
    # Remote path to pocketknife's cache
    # @private
    @VAR_POCKETKNIFE_CACHE = @VAR_POCKETKNIFE + "cache"
    # Remote path to temporary tarball containing uploaded files.
    # @private
    @VAR_POCKETKNIFE_TARBALL = @VAR_POCKETKNIFE_CACHE + "pocketknife.tmp"
    # Remote path to pocketknife's cookbooks
    # @private
    @VAR_POCKETKNIFE_COOKBOOKS = @VAR_POCKETKNIFE + "cookbooks"
    # Remote path to pocketknife's site-cookbooks
    # @private
    @VAR_POCKETKNIFE_SITE_COOKBOOKS = @VAR_POCKETKNIFE + "site-cookbooks"
    # Remote path to pocketknife's roles
    # @private
    @VAR_POCKETKNIFE_ROLES = @VAR_POCKETKNIFE + "roles"
    # Remote path to pocketknife's databags
    # @private
    @VAR_POCKETKNIFE_DATA_BAGS = @VAR_POCKETKNIFE + "data_bags"
    # Content of the solo.rb file
    # @private
    @SOLO_RB_CONTENT = <<-HERE
file_cache_path "#{@VAR_POCKETKNIFE_CACHE}"
cookbook_path ["#{@VAR_POCKETKNIFE_COOKBOOKS}", "#{@VAR_POCKETKNIFE_SITE_COOKBOOKS}"]
role_path "#{@VAR_POCKETKNIFE_ROLES}"
data_bag_path "#{@VAR_POCKETKNIFE_DATA_BAGS}"
cache_type "BasicFile"
cache_options({ :path => "#{@working_dir}/var/chef/cache/checksums", :skip_expires => true })
file_backup_path "#{@working_dir}/var/chef/backup"
    HERE
    # Remote path to chef-solo-apply
    # @private
    @CHEF_SOLO_APPLY = @working_dir + "usr/local/sbin/chef-solo-apply"
    # Remote path to csa
    # @private
    @CHEF_SOLO_APPLY_ALIAS = @CHEF_SOLO_APPLY.dirname + "csa"
    # Content of the chef-solo-apply file
    # @private
    @CHEF_SOLO_APPLY_CONTENT = <<-HERE
#!/bin/sh
chef-solo -j #{@NODE_JSON} "$@"
    HERE
      
      puts @ETC_CHEF
    end

    # Returns a Rye::Box connection.
    #
    # Caches result to {#connection_cache}.
    def connection
      return self.connection_cache ||= begin
          #rye = Rye::Box.new(self.name, :user => "root")
          puts "Connecting to.... #{self.name}"
          user = "root"
          if self.pocketknife.user != nil and self.pocketknife.user != ""
             user = self.pocketknife.user
          end
          if self.pocketknife.ssh_key != nil and self.pocketknife.ssh_key != ""
             puts "Connecting to.... #{self.name} as user #{user} with ssh key"
             rye = Rye::Box.new(self.name, {:user => user, :keys => self.pocketknife.ssh_key })
          else
             puts "Connecting to.... #{self.name} as user #{user}"
             rye = Rye::Box.new(self.name, {:user => user })
          end
          rye.disable_safe_mode
          rye
        end
    end

    # Displays status message.
    #
    # @param [String] message The message to display.
    # @param [Boolean] importance How important is this? +true+ means important, +nil+ means normal, +false+ means unimportant.
    def say(message, importance=nil)
      self.pocketknife.say("* #{self.name}: #{message}", importance)
    end

    # Returns path to this node's <tt>nodes/NAME.json</tt> file, used as <tt>node.json</tt> by <tt>chef-solo</tt>.
    #
    # @return [Pathname]
    def local_node_json_pathname
      return Pathname.new("nodes") + "#{self.name}.json"
    end

    # Does this node have the given executable?
    #
    # @param [String] executable A name of an executable, e.g. <tt>chef-solo</tt>.
    # @return [Boolean] Has executable?
    def has_executable?(executable)
      begin
        self.connection.execute(%{which "#{executable}" && test -x `which "#{executable}"`})
        return true
      rescue Rye::Err
        return false
      end
    end

    # Returns information describing the node.
    #
    # The information is formatted similar to this:
    #   {
    #     :distributor=>"Ubuntu", # String with distributor name
    #     :codename=>"maverick", # String with release codename
    #     :release=>"10.10", # String with release number
    #     :version=>10.1 # Float with release number
    #   }
    #
    # @return [Hash<String, Object] Return a hash describing the node, see above.
    # @raise [UnsupportedInstallationPlatform] Raised if there's no installation information for this platform.
    def platform
      return self.platform_cache ||= begin
        lsb_release = "/etc/lsb-release"
        begin
          output = self.connection.cat(lsb_release).to_s
          result = {}
          result[:distributor] = output[/DISTRIB_ID\s*=\s*(.+?)$/, 1]
          result[:release] = output[/DISTRIB_RELEASE\s*=\s*(.+?)$/, 1]
          result[:codename] = output[/DISTRIB_CODENAME\s*=\s*(.+?)$/, 1]
          result[:version] = result[:release].to_f

          if result[:distributor] && result[:release] && result[:codename] && result[:version]
            return result
          else
            raise UnsupportedInstallationPlatform.new("Can't install on node '#{self.name}' with invalid '#{lsb_release}' file", self.name)
          end
        rescue Rye::Err
          raise UnsupportedInstallationPlatform.new("Can't install on node '#{self.name}' without '#{lsb_release}'", self.name)
        end
      end
    end

    # Installs Chef and its dependencies on a node if needed.
    #
    # @raise [NotInstalling] Raised if Chef isn't installed, but user didn't allow installation.
    # @raise [UnsupportedInstallationPlatform] Raised if there's no installation information for this platform.
    def install
      unless self.has_executable?("chef-solo")
        case self.pocketknife.can_install
        when nil
          # Prompt for installation
          print "? #{self.name}: Chef not found. Install it and its dependencies? (Y/n) "
          STDOUT.flush
          answer = STDIN.gets.chomp
          case answer
          when /^y/i, ''
            # Continue with install
          else
            raise NotInstalling.new("Chef isn't installed on node '#{self.name}', but user doesn't want to install it.", self.name)
          end
        when true
          # User wanted us to install
        else
          # Don't install
          raise NotInstalling.new("Chef isn't installed on node '#{self.name}', but user doesn't want to install it.", self.name)
        end

        unless self.has_executable?("ruby")
          self.install_ruby
        end

        unless self.has_executable?("gem")
          self.install_rubygems
        end

        self.install_chef
      end
    end

    # Installs Chef on the remote node.
    def install_chef
      self.say("Installing chef...")
      self.execute("#{@sudo} gem install --no-rdoc --no-ri chef", true)
      self.say("Installed chef", false)
    end

    # Installs Rubygems on the remote node.
   def install_rubygems
     if @sudo != nil and @sudo != ""
       install_rubygems_sudo
     else      
      self.say("Installing rubygems...")
      self.execute(<<-HERE, true)
  cd /root &&      
  rm -rf rubygems-1.3.7 rubygems-1.3.7.tgz &&
  wget http://production.cf.rubygems.org/rubygems/rubygems-1.3.7.tgz &&
  tar zxf rubygems-1.3.7.tgz &&
  chmod -R a+rwX rubygems-1.3.7 &&
  cd rubygems-1.3.7 &&
  ruby setup.rb --no-format-executable &&
  rm -rf rubygems-1.3.7 rubygems-1.3.7.tgz
      HERE
      self.say("Installed rubygems", false)
     end
   end 

    def install_rubygems_sudo
      self.say("Installing rubygems sudo...")
      self.execute(<<-HERE, true)
  #{@sudo}rm -rf rubygems-1.3.7 rubygems-1.3.7.tgz &&
  #{@sudo}wget http://production.cf.rubygems.org/rubygems/rubygems-1.3.7.tgz &&
  #{@sudo}tar zxf rubygems-1.3.7.tgz &&
  #{@sudo}chmod -R a+rwX rubygems-1.3.7 &&
  cd rubygems-1.3.7 &&
  #{@sudo}ruby setup.rb --no-format-executable &&
  #{@sudo}rm -rf rubygems-1.3.7 rubygems-1.3.7.tgz
      HERE
      self.say("Installed rubygems", false)
    end

    # Installs Ruby on the remote node.
    def install_ruby
      command = \
        case self.platform[:distributor].downcase
        when /ubuntu/, /debian/, /gnu\/linux/
          "DEBIAN_FRONTEND=noninteractive sudo apt-get --yes install ruby ruby-dev libopenssl-ruby irb build-essential wget ssl-cert"
        when /centos/, /red hat/, /scientific linux/
          "yum -y install ruby ruby-shadow gcc gcc-c++ ruby-devel wget"
        else
          raise UnsupportedInstallationPlatform.new("Can't install on node '#{self.name}' with unknown distrubtor: `#{self.platform[:distrubtor]}`", self.name)
        end

      self.say("Installing ruby...")
      if self.platform[:distributor].downcase == "ubuntu"
         self.execute("sudo apt-get update", true)
      end   
      self.execute(command, true)
      self.say("Installed ruby", false)
    end

    # Prepares an upload, by creating a cache of shared files used by all nodes.
    #
    # IMPORTANT: This will create files and leave them behind. You should use the block syntax or manually call {cleanup_upload} when done.
    #
    # If an optional block is supplied, calls {cleanup_upload} automatically when done. This is typically used like:
    #
    #   Node.prepare_upload do
    #     mynode.upload
    #   end
    #
    # @yield [] Prepares the upload, executes the block, and cleans up the upload when done.
    def prepare_upload(&block)
      begin
        puts("prepare upload...")
        # TODO either do this in memory or scope this to the PID to allow concurrency
        TMP_SOLO_RB.open("w") {|h| h.write(@SOLO_RB_CONTENT)}
        TMP_CHEF_SOLO_APPLY.open("w") {|h| h.write(@CHEF_SOLO_APPLY_CONTENT)}
        # minitar gem on windows tar file corrupt so use alternative command
        if RUBY_PLATFORM.index("mswin") != nil or RUBY_PLATFORM.index("i386-mingw32") != nil
           puts "On windows using tar.exe...."
           puts "#{ENV['EC2DREAM_HOME']}/tar/tar.exe cvf #{TMP_TARBALL.to_s} #{VAR_POCKETKNIFE_COOKBOOKS.basename.to_s} #{VAR_POCKETKNIFE_SITE_COOKBOOKS.basename.to_s} #{VAR_POCKETKNIFE_ROLES.basename.to_s} #{TMP_SOLO_RB.to_s} #{TMP_CHEF_SOLO_APPLY.to_s}" 
           system "#{ENV['EC2DREAM_HOME']}/tar/tar.exe cvf #{TMP_TARBALL.to_s} #{VAR_POCKETKNIFE_COOKBOOKS.basename.to_s} #{VAR_POCKETKNIFE_SITE_COOKBOOKS.basename.to_s} #{VAR_POCKETKNIFE_ROLES.basename.to_s} #{TMP_SOLO_RB.to_s} #{TMP_CHEF_SOLO_APPLY.to_s}" 
        else
           puts("TMP_TARBALL=#{TMP_TARBALL} contains following files:")
           puts("VAR_POCKETKNIFE_COOKBOOKS=#{VAR_POCKETKNIFE_COOKBOOKS}")
           puts("VAR_POCKETKNIFE_SITE_COOKBOOKS=#{VAR_POCKETKNIFE_SITE_COOKBOOKS}")
           puts("VAR_POCKETKNIFE_ROLES=#{VAR_POCKETKNIFE_ROLES}")
           puts("TMP_SOLO_RB=#{TMP_SOLO_RB}")
           puts("VAR_POCKETKNIFE_CACHE=#{VAR_POCKETKNIFE_CACHE}")
        
           TMP_TARBALL.open("w") do |handle|
             Archive::Tar::Minitar.pack(
              [
               VAR_POCKETKNIFE_COOKBOOKS.basename.to_s,
               VAR_POCKETKNIFE_SITE_COOKBOOKS.basename.to_s,
               VAR_POCKETKNIFE_ROLES.basename.to_s,
               TMP_SOLO_RB.to_s,
               TMP_CHEF_SOLO_APPLY.to_s
              ],
              handle
             )
           end  
        end
      rescue Exception => e
        cleanup_upload
        raise e
      end

      if block
        begin
          yield(self)
        ensure
          cleanup_upload
        end
      end
    end

    # Cleans up cache of shared files uploaded to all nodes. This cache is created by the {prepare_upload} method.
    def cleanup_upload
      [
        TMP_TARBALL,
        TMP_SOLO_RB,
        TMP_CHEF_SOLO_APPLY
      ].each do |path|
      	puts "delete #{path}"
        path.unlink if path.exist?
      end
    end

   # Uploads configuration information to node.
   #
   # IMPORTANT: You must first call {prepare_upload} to create the shared files that will be uploaded.
   def upload
     if @sudo != nil and @sudo != ""
       upload_sudo
     else   
       self.say("Uploading configuration...")
 
       self.say("Removing old files...", false)
       self.execute <<-HERE
    umask 0377 &&
   rm -rf "#{ETC_CHEF}" "#{VAR_POCKETKNIFE}" "#{VAR_POCKETKNIFE_CACHE}" "#{CHEF_SOLO_APPLY}" "#{CHEF_SOLO_APPLY_ALIAS}" &&
   mkdir -p "#{ETC_CHEF}" "#{VAR_POCKETKNIFE}" "#{VAR_POCKETKNIFE_CACHE}" "#{CHEF_SOLO_APPLY.dirname}" 
   HERE
 
       self.say("Uploading new files...", false)
       self.say("Uploading #{self.local_node_json_pathname} to #{NODE_JSON}", false)
       self.connection.file_upload(self.local_node_json_pathname.to_s, NODE_JSON.to_s)
       self.connection.file_upload(TMP_TARBALL.to_s, VAR_POCKETKNIFE_TARBALL.to_s)
       self.say("Installing new files...", false)
       self.execute <<-HERE, true
   cd "#{VAR_POCKETKNIFE_CACHE}" &&
   tar xvf "#{VAR_POCKETKNIFE_TARBALL}" &&
   chmod -R u+rwX,go= . &&
   chown -R root:root . &&
   mv "#{TMP_SOLO_RB}" "#{SOLO_RB}" &&
   mv "#{TMP_CHEF_SOLO_APPLY}" "#{CHEF_SOLO_APPLY}" &&
   chmod u+x "#{CHEF_SOLO_APPLY}" &&
   ln -s "#{CHEF_SOLO_APPLY.basename}" "#{CHEF_SOLO_APPLY_ALIAS}" &&
   rm "#{VAR_POCKETKNIFE_TARBALL}" &&
   mv * "#{VAR_POCKETKNIFE}"
       HERE
 
       self.say("Finished uploading!", false)
    end
 end   

    # Uploads configuration information to node.
    #
    # IMPORTANT: You must first call {prepare_upload} to create the shared files that will be uploaded.
    def upload_sudo
      self.say("Uploading configuration using sudo...")

      self.say("Removing old files...", false)
      self.execute <<-HERE
   umask 0377 &&
  #{@sudo}rm -rf "#{@ETC_CHEF}" "#{@VAR_POCKETKNIFE}" "#{@VAR_POCKETKNIFE_CACHE}" "#{@CHEF_SOLO_APPLY}" "#{@CHEF_SOLO_APPLY_ALIAS}" &&
  #{@sudo}mkdir -p "#{@ETC_CHEF}" "#{@VAR_POCKETKNIFE}" "#{@VAR_POCKETKNIFE_CACHE}" "#{@CHEF_SOLO_APPLY.dirname}" &&
  #{@sudo}chmod -R a+rwX "#{@ETC_CHEF}" &&
  #{@sudo}chmod -R a+rwX "#{@VAR_POCKETKNIFE}" &&
  #{@sudo}chmod -R a+rwX "#{@VAR_POCKETKNIFE_CACHE}"
  HERE

      self.say("Uploading new files... from #{self.local_node_json_pathname.to_s} to #{@NODE_JSON.to_s}", false)
      self.say("and from #{TMP_TARBALL.to_s} to #{@VAR_POCKETKNIFE_TARBALL.to_s}", false)
      self.connection.file_upload(self.local_node_json_pathname.to_s, @NODE_JSON.to_s)
      self.connection.file_upload(TMP_TARBALL.to_s, @VAR_POCKETKNIFE_TARBALL.to_s)

      self.say("Installing new files...", false)
      self.execute <<-HERE, true
  cd "#{@VAR_POCKETKNIFE_CACHE}" &&
  #{@sudo}tar xvf "#{@VAR_POCKETKNIFE_TARBALL}" &&
  #{@sudo}chmod -R a+rwX "#{@VAR_POCKETKNIFE_CACHE}"  &&
  #{@sudo}mv "#{TMP_SOLO_RB}" "#{@SOLO_RB}" &&
  #{@sudo}mv "#{TMP_CHEF_SOLO_APPLY}" "#{@CHEF_SOLO_APPLY}" &&
  #{@sudo}chmod u+x "#{@CHEF_SOLO_APPLY}" &&
  #{@sudo}ln -s "#{@CHEF_SOLO_APPLY.basename}" "#{@CHEF_SOLO_APPLY_ALIAS}" &&
  #{@sudo}rm "#{@VAR_POCKETKNIFE_TARBALL}" &&
  #{@sudo}mv * "#{@VAR_POCKETKNIFE}"
      HERE

      self.say("Finished uploading!", false)
    end
    
 

    

    # Applies the configuration to the node. Installs Chef, Ruby and Rubygems if needed.
    def apply
      self.install

      self.say("Applying configuration...", true)
      command = "#{@sudo}chef-solo -j #{@NODE_JSON} -c #{@SOLO_RB}"
      command << " -l debug" if self.pocketknife.verbosity == true
      self.execute(command, true)
      self.say("Finished applying!")
    end

    # Deploys the configuration to the node, which calls {#upload} and {#apply}.
    def deploy
      puts "Deploys the configuration to the node, which calls {#upload} and {#apply}."
      prepare_upload {upload}
      self.apply
    end

    # Executes commands on the external node.
    #
    # @param [String] commands Shell commands to execute.
    # @param [Boolean] immediate Display execution information immediately to STDOUT, rather than returning it as an object when done.
    # @return [Rye::Rap] A result object describing the completed execution.
    # @raise [ExecutionError] Raised if something goes wrong with execution.
    def execute(commands, immediate=false)
      self.say("Executing:\n#{commands}", false)
      if immediate
        self.connection.stdout_hook {|line| puts line}
      end
      return self.connection.execute("(#{commands}) 2>&1")
    rescue Rye::Err => e
      raise Pocketknife::ExecutionError.new(self.name, commands, e, immediate)
    ensure
      self.connection.stdout_hook = nil
    end


    # Remote path to pocketknife's cache
    # @private
    VAR_POCKETKNIFE_CACHE = Pathname.new("cache")
    # Remote path to temporary tarball containing uploaded files.
    # @private
    VAR_POCKETKNIFE_COOKBOOKS = Pathname.new("cookbooks")
    # Remote path to pocketknife's site-cookbooks
    # @private
    VAR_POCKETKNIFE_SITE_COOKBOOKS = Pathname.new("site-cookbooks")
    # Remote path to pocketknife's roles
    # @private
    VAR_POCKETKNIFE_ROLES = Pathname.new("roles")
    # Remote path to pocketknife's databags
    # @private
    VAR_POCKETKNIFE_DATA_BAGS = Pathname.new("data_bags")
    # Local path to solo.rb that will be included in the tarball
    # @private
    TMP_SOLO_RB = Pathname.new("solo.rb.tmp")
    # Local path to chef-solo-apply.rb that will be included in the tarball
    # @private
    TMP_CHEF_SOLO_APPLY = Pathname.new("chef-solo-apply.tmp")
    # Local path to the tarball to upload to the remote node containing shared files
    # @private
    TMP_TARBALL = Pathname.new("pocketknife.tmp")
  end
end
