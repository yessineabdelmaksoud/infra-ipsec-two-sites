#!/usr/bin/env python3
"""Type the OPNsense first-boot console steps for you, over the serial console.

Does exactly what a person would do in `virsh console <vm>`:
  wait for boot -> login root/opnsense -> option 2 for LAN -> option 2 for WAN
Interface assignment is not needed: on first boot OPNsense auto-assigns
vtnet0 = LAN and vtnet1 = WAN (the order of the VM's network cards).
Prompts were recorded on OPNsense 26.7; the whole session is written to --log.
"""
import argparse
import sys

import pexpect

MENU = r'Enter an option:'
YN = r'\? \[[yY]/[nN]\]'


def answer_until(child, answers, done, timeout=120):
    """Reply to each prompt in `answers` (regex -> reply) until `done` appears."""
    patterns = [done] + list(answers)
    while True:
        i = child.expect(patterns, timeout=timeout)
        if i == 0:
            return
        child.sendline(answers[patterns[i]])


def wait_for_login(child, password, fresh):
    """Log in as root. On a fresh boot, only wait: any key pressed during boot
    would start the config importer or the manual interface assignment."""
    if not fresh:
        child.sendline('')
    while True:
        i = child.expect([r'login: ', MENU, r'Select device to import from'])
        if i == 0:
            child.sendline('root')
            child.expect('Password:')
            child.sendline(password)
            child.expect(MENU, timeout=60)
            return
        if i == 1:
            return
        child.sendline('')  # importer started anyway: leave it


def set_address(child, name, ip, prefix, gateway=''):
    """Console option 2 for the interface labelled `name` (LAN or WAN)."""
    child.sendline('2')
    child.expect(r'(\d+) - ' + name + r' \(')
    number = child.match.group(1)
    child.expect(r'Enter the number of the interface to configure:')
    child.sendline(number)
    prompt = r'\s*\r?\n> ?'
    answer_until(child, {
        r'IPv4 address \w+ interface via DHCP' + YN: 'n',
        r'Enter the new \w+ IPv4 address\. Press <ENTER> for none:' + prompt: ip,
        r'Enter the new \w+ IPv4 subnet bit count \(1 to 32\):' + prompt: str(prefix),
        r'For a LAN, press <ENTER> for none:' + prompt: gateway,
        r'use the gateway as the IPv4 name server, too' + YN: 'n',
        r'Enter the IPv4 name server or press <ENTER> for none:': '',
        r'via WAN tracking' + YN: 'n',
        r'via DHCP6' + YN: 'n',
        r'Enter the new \w+ IPv6 address\. Press <ENTER> for none:' + prompt: '',
        r'enable the DHCP server on \w+' + YN: 'n',
        r'from HTTPS to HTTP' + YN: 'n',
        r'new self-signed web GUI certificate' + YN: 'n',
        r'Restore web GUI access defaults' + YN: 'n',
        r'Press <ENTER> to continue': '',
    }, MENU)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--uri', default='qemu:///system')
    p.add_argument('--domain', required=True)
    p.add_argument('--password', default='opnsense', help='root password (factory default)')
    p.add_argument('--lan', required=True, help='LAN address/prefix, e.g. 10.0.2.1/24')
    p.add_argument('--wan', required=True, help='WAN address/prefix, e.g. 192.168.100.11/24')
    p.add_argument('--wan-gateway', required=True)
    p.add_argument('--log', required=True)
    p.add_argument('--boot-timeout', type=int, default=600)
    p.add_argument('--fresh', action='store_true', help='VM was just started: wait for boot without typing')
    args = p.parse_args()

    child = pexpect.spawn('virsh', ['-c', args.uri, 'console', '--force', args.domain],
                          encoding='utf-8', codec_errors='replace', timeout=args.boot_timeout)
    with open(args.log, 'w') as log:
        child.logfile_read = log
        child.expect('Escape character')
        wait_for_login(child, args.password, args.fresh)
        lan_ip, lan_prefix = args.lan.split('/')
        wan_ip, wan_prefix = args.wan.split('/')
        set_address(child, 'LAN', lan_ip, lan_prefix)
        set_address(child, 'WAN', wan_ip, wan_prefix, args.wan_gateway)
        child.sendline('0')  # log out, leave the console at the login prompt
        child.expect(r'login: ', timeout=30)
        child.sendcontrol(']')
    return 0


if __name__ == '__main__':
    sys.exit(main())
