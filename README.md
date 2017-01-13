Redmine to GitHub
=================

This is a collection of scripts used to migrate issues from Redmine to Github.

## Concept

The idea is to transfer as much data as possible, so the Redmine installation
is no more needed.

But there should be a way to link properly to GitHub.

    https://redmine.example.com/issues/1234
    redirects to -> https://github.com/example/awesome/issues/45
    
* All important issue data is put into the new GitHub issue description
     * Meta data
     * Original description
     * Relations
     * Custom fields
     * Notes and changes
* Some data will me transfered into GitHub meta data
     * Status -> Labels
     * Category -> Tags
     * Assignee (from a map in settings.yml)
     * Milestone

## Installation

    bundle install
    
Copy `settings.example.yml` to `settings.yml` and setup your environment.

## Usage

    ./dump_redmine_versions.rb -R awesome
    ./dump_redmine_issues.rb -R awesome

Now have a look into the generated dump directory. This will give you an idea
what issues will be migrated, and what the result will look like.

TODO: push to GitHub

## License

    Copyright (C) 2017 Markus Frosch <markus.frosch@icinga.com>

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program; if not, write to the Free Software Foundation, Inc.,
    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
