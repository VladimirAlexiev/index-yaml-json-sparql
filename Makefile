all: elastic-index-expanded.yaml elastic-index.json elastic-index.ru

elastic-index.ru: elastic-index.yaml
	perl -S index-yaml-json-sparql.pl --index=datasets        $^ > $@

elastic-index-expanded.yaml: elastic-index.yaml
	perl -S index-yaml-json-sparql.pl --index=datasets --yaml $^ > $@

elastic-index.json: elastic-index.yaml
	perl -S index-yaml-json-sparql.pl --index=datasets --json $^ > $@
