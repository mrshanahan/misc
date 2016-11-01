import os.path
import re
import sys
import urllib2

chicago_weather_url = "http://forecast.weather.gov/product.php?site=lot&product=ZFP&issuedby=lot"

def main():
	prog = os.path.split(sys.argv[0])[1]
	matchstr = r'.*'
	args = sys.argv[1:]
	i = 0
	while i < len(args):
		arg = args[i]
		if arg == "-s" or arg == "--section":
			if i == len(args)-1:
				print >> sys.stderr, "%s: error: option -s needs argument" % prog
				sys.exit(-1)
			matchstr = args[i+1]
			i += 2
		else:
			print >> sys.stderr, '%s: warning: ignoring unknown argument "%s"' % (prog, arg)
			i += 1
	line_match_patt = re.compile(matchstr)
	body = None
	try:
		body = urllib2.urlopen(chicago_weather_url).read()
	except urllib2.URLError, e:
		print >> sys.stderr, "%s: error: bad URL (tried: %s; received: %s)" % (prog, chicago_weather_url, str(e))
		sys.exit(-1)
	if not body:
		print >> sys.stderr, "%s: error: no data received; check your connection and the provided URL"
		sys.exit(-1)
	forecasts = re.search('<pre class="glossaryProduct">(.*?)</pre>', body, re.S).group(1).strip().split('\n$$\n')
	chicago_forecast = [f for f in forecasts if 'INCLUDING THE CITY OF...CHICAGO' in f][0]
	for line in chicago_forecast.split('\n'):
		if line_match_patt.match(line):
			print line
	
if __name__ == '__main__':
	main()