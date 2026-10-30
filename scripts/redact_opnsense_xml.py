#!/usr/bin/env python3
"""Copy an OPNsense config.xml with its secrets replaced by "REDACTED".

The export is a project deliverable, but the raw file holds password hashes,
private keys and the IPsec pre-shared key: never publish it as is.

  redact_opnsense_xml.py <config.xml> <output.xml>
"""
import sys
import xml.etree.ElementTree as ET

# Element names whose text is secret (legacy and MVC parts of config.xml).
SECRET_TAGS = {
    'password', 'bcrypt-hash', 'sha512-hash', 'prv', 'pre-shared-key', 'Key',
    'secret', 'otp_seed', 'apikeys', 'pass', 'psk', 'authorizedkeys_secret',
}


def redact(tree):
    count = 0
    for el in tree.iter():
        if el.tag in SECRET_TAGS and ((el.text or '').strip() or len(el)):
            el.text = 'REDACTED'
            for child in list(el):
                el.remove(child)
            count += 1
    return count


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    tree = ET.parse(sys.argv[1])
    count = redact(tree)
    tree.write(sys.argv[2], encoding='utf-8', xml_declaration=True)
    print(f'{count} secret values redacted -> {sys.argv[2]}')


if __name__ == '__main__':
    main()
