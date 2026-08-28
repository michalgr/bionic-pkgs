import urllib.request
import json
import sys

run_id = "33130368280"
url = f"https://api.github.com/repos/michalgr/bionic-pkgs/actions/runs/{run_id}/jobs"
req = urllib.request.Request(url, headers={"Accept": "application/vnd.github.v3+json"})
try:
    response = urllib.request.urlopen(req)
    data = json.loads(response.read())
    print("Found jobs:")
    for job in data.get('jobs', []):
        print(f"ID: {job['id']}, Name: {job['name']}, Conclusion: {job['conclusion']}")
except Exception as e:
    print(f"Error fetching jobs: {e}")
