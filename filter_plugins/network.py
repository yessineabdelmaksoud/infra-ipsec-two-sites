"""Jinja filters for the lab addressing plan."""


def mac_from_ip(ip):
    """Stable, unique MAC from an IPv4 address: 10.0.2.7 -> 52:54:00:00:02:07."""
    octets = [int(o) for o in str(ip).split('.')]
    return '52:54:00:%02x:%02x:%02x' % tuple(octets[1:])


class FilterModule:
    def filters(self):
        return {'mac_from_ip': mac_from_ip}
