pocketknife
===========

`pocketknife` is a devops tool for managing computers running `chef-solo`, powered by [Opscode Chef](http://www.opscode.com/chef/).

Using `pocketknife`, you create a project that describes the configuration of your computers and then deploy it to bring them to their intended state.

With `pocketknife`, you don't need to setup or manage a specialized `chef-server` node or rely on an unreliable network connection to a distant hosted service whose security you don't control, deal with managing `chef`'s security keys, or deal with manually synchronizing data with the `chef-server` datastore.

With `pocketknife`, all of your cookbooks, roles, data_bags and nodes are stored in easy-to-use files that you can edit, share, backup and version control with tools you already have.

The original version of PocketKnife (from Igal), at time or writing, assumes Chef-solo will be executed as root and assumes the default location of the SSH key. Sometimes you don't have and don't need the root credentials to deploy. It could happen when you want to use Chef to deploy an application or the artifacts of an application that will run as a specific user. This happens when you're a dev team that needs to regularly deploy enterprise application components (as opposed to the traditional use case of being an infrastructure team that has the admin access on the machine anyway). This could be used for automatic deployment and testing within a continuous integration environment.

Follow a tutorial with [a repo for Chef used with pocketknife](https://github.com/matlux/pocketknife).

Comparisons
-----------

Why create another tool?

* `knife` is included with `chef` and is primarily used for managing client-server nodes. The `pocketknife` name plays off this by virtue that it's a smaller, more personal way of managing nodes.
* `chef-client` is included with `chef`, but you typically need to install another node to act as a `chef-server`, which takes more resources and effort. Using `chef` in client-server mode provides benefits like network-wide databags and pull-based updates, but if you can live without these, `pocketknife` can save you a lot of effort.
* `chef-solo` is included as part of `chef`, and `pocketknife` uses it. However, `chef-solo` is a low-level tool, and creating and deploying all the files it needs is a significant chore. It also provides no way of deploying or managing your shared and node-specific configuration files. `pocketknife` provides all the missing functionality for creating, managing and deploying, so you don't have to use `chef-solo` directly.
* `littlechef` is the inspiration for `pocketknife`, it's a great project that I've contributed to and you should definitely [evaluate it](https://github.com/tobami/littlechef). I feel that `pocketknife` offers a more robust, repeatable and automated mechanism for deploying remote nodes; has better documentation, default behavior and command-line support; has good tests and a clearer, more maintainable design; and is written in Ruby so you use the same stack as `chef`.

The Extra features Contained in this fork
_________________________________________

* Run Chef-solo as any user.
* define the location of a specific SSH identity Key
* use password file instead of ssh identity key
* All remote files are stored under /tmp in order to be accessible by any user that is used by pocketknife.

Usage
-----

Install the software on the machine you'll be running `pocketknife` on, this is a computer that will deploy configurations to other computers:

* Install Ruby: http://www.ruby-lang.org/
* Install Rubygems: http://rubygems.org/
* Install `archive-tar-minitar`: `gem install archive-tar-minitar` - pocketknife dependency.
* Install `rye`: `gem install rye` - pocketknife dependency.
* `cd /path/of/your/choice`
* `git clone git://github.com/matlux/pocketknife.git`
* `export PATH=/path/of/your/choice/pocketknife:$PATH` - add pocketknife to your PATH

    /path/of/your/choice/pocketknife/bin/pocketknife

Create a new *project*, a special directory that will contain your configuration files. For example, create the `myNewProject` project directory by running:

    pocketknife --create myNewProject

Go into your new *project* directory:

    cd myNewProject

Create cookbooks in the `cookbooks` directory that describe how your computers should be configured. These are standard `chef` cookbooks, like the [opscode/cookbooks](https://github.com/opscode/cookbooks). You can find an example, follow a tutorial and download a copy of [chef-cookbooks-repo/cookbooks/myapp](https://github.com/matlux/chef-cookbooks-repo) as `cookbooks/myapp`.

Override cookbooks in the `site-cookbooks` directory. This has the same structure as `cookbooks`, but any files you put here will override the contents of `cookbooks`. This is useful for storing the original code of a third-party cookbook in `cookbooks` and putting your customizations in `site-cookbooks`.

Define roles in the `roles` directory that describe common behavior and attributes of your computers using JSON syntax using [chef's documentation](http://wiki.opscode.com/display/chef/Roles#Roles-AsJSON). For example, define a role called `myapp1` by creating a file called `roles/myapp1.json` with this content:

    {
      "name": "myapp1",
      "chef_type": "role",
      "json_class": "Chef::Role",
      "run_list": [
        "recipe[myapp]"
      ],
      "override_attributes": {
        "myapp": {
          "instanceReq": 2
        }
      }
    }

Define a new node using the `chef` JSON syntax for [runlist](http://wiki.opscode.com/display/chef/Setting+the+run_list+in+JSON+during+run+time) and [attributes](http://wiki.opscode.com/display/chef/Attributes). For example, to define a node with the hostname `henrietta.swa.gov.it` create the `nodes/henrietta.swa.gov.it.json` file, and add the contents below so it uses the `myapp1` role and overrides its attributes to use a local myapp1 server:

    {
      "run_list": [
        "role[uat]",
        "role[myapp1]"
      ],
      "myapp": {
          "instanceNumber": 3
        }
    }

Operations on remote nodes will be performed using SSH. You should consider [configuring ssh-agent](http://mah.everybody.org/docs/ssh) so you don't have to keep typing in your passwords.

Finally, deploy your configuration to the remote machine and see the results. For example, lets deploy the above configuration to the `henrietta.swa.gov.it` host, which can be abbreviated as `henrietta` when calling `pocketknife`:

    pocketknife henrietta

When deploying a configuration to a node, `pocketknife` will check whether Chef and its dependencies are installed. It something is missing, it will prompt you for whether you'd like to have it install them automatically.

To always install Chef and its dependencies when they're needed, without prompts, use the `-i` option, e.g. `pocketknife -i henrietta`. Or to never install Chef and its dependencies, use the `-I` option, which will cause the program to quit with an error rather than prompting if Chef or its dependencies aren't installed.

If something goes wrong while deploying the configuration, you can display verbose logging from `pocketknife` and Chef by using the `-v` option. For example, deploy the configuration to `henrietta` with verbose logging:

    pocketknife -v henrietta

How to use the new features:

Imagine you want pocketknife to execute chef-solo onto a remote machine without root access. What would you do? You can use the `--user` option to do that. It will either function interactivelly if you enter the password or it will make use of an ssh key in it's default location:

    pocketknife --user bob henrietta

Imagine you're not using a default location of the ssh key, you can use the `--sshkey` option:

    pocketknife --user bob --sshkey ~/.ssh/id_rsa_alt henrietta

Now imagine that your organisation has banned the use of ssh keys and you are fed up with repeatedly typing your password or want to automate the procedure. Then use the following argument:

    pocketknife --user bob --password password.txt henrietta

The password file should contain a list of user and passwords as follow:

    bob: bobpassword
    user2: password2
    user3: password3

If you really need to debug on the remote machine, you may be interested about some of the commands and paths:

* `chef-solo-apply` (/tmp/usr/local/sbin/chef-solo-apply) will apply the configuration to the machine. You can specify `-l debug` to make it more verbose. Run it with `-h` for help.
* `csa` (/tmp/usr/local/sbin/csa) is a shortcut for `chef-solo-apply` and accepts the same arguments.
* `/tmp/etc/chef/solo.rb` contains the `chef-solo` configuration settings.
* `/tmp/etc/chef/node.json` contains the node-specific configuration, like the `runlist` and attributes.
* `/tmp/var/local/pocketknife` contains the `cookbooks`, `site-cookbooks` and `roles` describing your configuration.

Contributing
------------

This software is published as open source at https://github.com/matlux/pocketknife

You can view and file issues for this software at https://github.com/matlux/pocketknife/issues

If you'd like to contribute code or documentation:

* Check out the latest master to make sure the feature hasn't been implemented or the bug hasn't been fixed yet
* Check out the issue tracker to make sure someone already hasn't requested it and/or contributed it
* Fork the project
* Start a feature/bugfix branch
* Commit and push until you are happy with your contribution
* Make sure to add tests for it. This is important so I don't break it in a future version unintentionally.
* Please try not to mess with the Rakefile, version, or history. If you want to have your own version, or is otherwise necessary, that is fine, but please isolate to its own commit so I can cherry-pick around it.
* Submit a pull request using github, this makes it easy for me to incorporate your code.

Copyright
---------

Copyright (c) 2012 Mathieu Gauthron. See `LICENSE.txt` for further details.
