#!/usr/bin/python
# -*- coding: utf-8 -*-

# (c) 2015, Ritesh Khadgaray <khadgaray () gmail.com>
#
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


try:
    from pyVmomi import vim, vmodl
    HAS_PYVMOMI = True
except ImportError:
    HAS_PYVMOMI = False

def find_vm(content, vm_id, vm_id_type="dns_name", datacenter=None):
    si = content.searchIndex
    vm = None

    if datacenter:
        datacenter = find_datacenter_by_name(content, datacenter)

    if vm_id_type == 'dns_name':
        vm = si.FindByDnsName(datacenter=datacenter, dnsName=vm_id, vmSearch=True)
    elif vm_id_type == 'inventory_path':
        vm = si.FindByInventoryPath(inventoryPath=vm_id)
        if type(vm) != type(vim.VirtualMachine):
            vm = None
    elif vm_id_type == 'uuid':
        vm = si.FindByUuid(datacenter=datacenter, uuid=vm_id, vmSearch=True)
    elif vm_id_type == 'vm_name':
        for machine in get_all_objs(content, [vim.VirtualMachine]):
            if machine.name == vm_id:
                vm = machine

    return vm

# https://github.com/vmware/pyvmomi-community-samples/blob/master/samples/execute_program_in_vm.py
def execute_command(content, vm, vm_username, vm_password, program_path, args="", env=None, cwd=None):

    creds = vim.vm.guest.NamePasswordAuthentication(username=vm_username, password=vm_password)
    cmdspec = vim.vm.guest.ProcessManager.ProgramSpec(arguments=args, envVariables=env, programPath=program_path, workingDirectory=cwd)
    cmdpid = content.guestOperationsManager.processManager.StartProgramInGuest(vm=vm, auth=creds, spec=cmdspec)

    return cmdpid

def main():

    argument_spec = vmware_argument_spec()
    argument_spec.update(dict(datacenter=dict(default=None, type='str'),
                              vm_id=dict(required=True, type='str'),
                              vm_id_type=dict(default='vm_name', type='str', choices=['inventory_path', 'uuid', 'dns_name', 'vm_name']),
                              vm_username=dict(required=False, type='str'),
                              vm_password=dict(required=False, type='str', no_log=True),
                              vm_shell=dict(required=True, type='str'),
                              vm_shell_args=dict(default=" ", type='str'),
                              vm_shell_env=dict(default=None, type='list'),
                              vm_shell_cwd=dict(default=None, type='str')))

    module = AnsibleModule(argument_spec=argument_spec, supports_check_mode=False)

    if not HAS_PYVMOMI:
        module.fail_json(msg='pyvmomi is required for this module')

    try:
        p = module.params
        content = connect_to_api(module)

        vm = find_vm(content, p['vm_id'], p['vm_id_type'], p['datacenter'])
        if not vm:
            module.fail_json(msg='failed to find VM')

        msg = execute_command(content, vm, p['vm_username'], p['vm_password'],
                              p['vm_shell'], p['vm_shell_args'], p['vm_shell_env'], p['vm_shell_cwd'])

        module.exit_json(changed=False, virtual_machines=vm.name, msg=msg)
    except vmodl.RuntimeFault as runtime_fault:
        module.fail_json(msg=runtime_fault.msg)
    except vmodl.MethodFault as method_fault:
        module.fail_json(msg=method_fault.msg)
    except Exception as e:
        module.fail_json(msg=str(e))

from ansible.module_utils.vmware import *
from ansible.module_utils.basic import *

if __name__ == '__main__':
    main()


