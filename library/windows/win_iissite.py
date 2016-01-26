#!/usr/bin/python
# This file is part of Ansible
#
# Ansible is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# Ansible is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Ansible.  If not, see <http://www.gnu.org/licenses/>.

# this is a windows documentation stub, actual code lives in the .ps1
# file of the same name

DOCUMENTATION = '''
---
module: win_iissite
version_added: "1.0"
short_description: creates iis web app
description:
     - Creates an iss web app in the default web site
options:
  vrootdir:
    description:
      - Source path
    required: true
    default: null
    aliases: []
  vdirname:
    description:
      - Dest path
    required: true
    default: null
    aliases: []
  apppool:
    description:
      - Dest path
    required: true
    default: null
    aliases: []
author: John Hamill
'''

EXAMPLES = '''
# Obtain information about a file

- win_stat: path=C:\\foo.ini
  register: file_info

- debug: var=file_info
'''

