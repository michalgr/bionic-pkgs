import urllib.request
import sys

job_id = "98718315829"
url = f"https://api.github.com/repos/michalgr/bionic-pkgs/actions/jobs/{job_id}/logs"
req = urllib.request.Request(url, headers={"Accept": "application/vnd.github.v3+json"})
try:
    response = urllib.request.urlopen(req)
    with open('log.txt', 'wb') as f:
        f.write(response.read())
except Exception as e:
    print(f"Error fetching log: {e}")
