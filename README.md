# portforward-proton

**automatically set up port-forwarding for protonvpn on linux**

## what is it?

it automates everything you would need to do manually here:

https://protonvpn.com/support/port-forwarding-manual-setup#linux


## what does it do?

- checks if the system is connected to a server that actually supports port-forwarding
- checks if qBittorrent is installed and changes the outbound port to the one it was given
- checks if ufw is installed and adds a rule to allow the port
- on exit, it deletes the ufw rule, so the port doesn't stay open longer than needed.

### supported torrent clients:

- qBittorrent

** NOTE: qBittorrent's settings will only be changed if it isn't running**

(i might look into transmission and deluge in the future, but i won't promise anything.)


### supported firewalls:

- ufw


test it & report bugs or feedback/suggestions.

**Cheers, ConzZah**
