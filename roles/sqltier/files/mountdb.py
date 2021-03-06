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
module: mountdb
version_added: "1.7"
short_description: mounts a sql database
description:
     - Returns information about a Windows file
options:
  SQLInstance:
    description:
      - The full path of the file/object to get the facts of; both forward and
        back slashes are accepted.
    required: true
    default: null
    aliases: []
  databaseName:
    description:
      - Name of mounted db
    required: true
    default: yes
    aliases: []
  databasePath:
    description:
      - Path to back up files
    required: true
    default: yes
    aliases: []
author: Chris Church
'''

EXAMPLES = '''
# Obtain information about a file

- win_stat: path=C:\\foo.ini
  register: file_info

- debug: var=file_info
'''

