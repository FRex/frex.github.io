.PHONY: all

all: python-top-code-speed.html

python-top-code-speed.html: makearticle.py python-top-code-speed.md article-template.html
	python3 makearticle.py python-top-code-speed.md "Python top-level slower than functions" "programming article about why python code at the top level is slower than in functions"
