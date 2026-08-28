import urllib.request
content = urllib.request.urlopen("https://raw.githubusercontent.com/michalgr/bionic-pkgs/main/pkgs/default.nix").read().decode('utf-8')
print("bash" in content)
