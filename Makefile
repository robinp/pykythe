# Simple scripts for testing etc.

# Assume that ../kythe has been cloned from
# https://github.com/google/kythe and has been built with `bazel build
# //...` and that the latest Kythe tarball has been downloaded and
# installed in /opt/kythe.

KYTHE=../kythe
KYTHE_BIN=$(KYTHE)/bazel-bin
VERIFIER_EXE=$(KYTHE_BIN)/kythe/cxx/verifier/verifier
# VERIFIER_EXE=/opt/kythe/tools/verifier
ENTRYSTREAM_EXE=$(KYTHE_BIN)/kythe/go/platform/tools/entrystream/linux_amd64_stripped/entrystream
# ENTRYSTREAM_EXE=/opt/kythe/tools/entrystream
WRITE_ENTRIES_EXE=$(KYTHE_BIN)/kythe/go/storage/tools/write_entries/linux_amd64_stripped/write_entries
WRITE_TABLES_EXE=$(KYTHE_BIN)/kythe/go/serving/tools/write_tables/linux_amd64_stripped/write_tables
# http_server built from source requires some additional post-processing,
#     so use the old http_server from Kythe v0.0.26
# HTTP_SERVER_EXE=$(KYTHE_BIN)/kythe/go/serving/tools/http_server/linux_amd64_stripped/http_server
TRIPLES_EXE=$(KYTHE_BIN)/kythe/go/storage/tools/triples/linux_amd64_stripped/triples
HTTP_SERVER_EXE=/opt/kythe/tools/http_server
KYTHE_EXE=$(KYTHE_BIN)/kythe/go/serving/tools/kythe/linux_amd64_stripped/kythe
# assume that /opt/kythe has been set up from
# https://github.com/google/kythe/releases/download/v0.0.26/kythe-v0.0.26.tar.gz
HTTP_SERVER_RESOURCES=/opt/kythe/web/ui
# TODO: use an array for TEST_GRAMMAR_FILES
TEST_GRAMMAR_FILE=py3_test_grammar
TEST_GRAMMAR_FILE2=bindings
TEST_GRAMMAR_FILE3=simple
TEST_GRAMMAR_DIR=test_data
TESTGITHUB=$(HOME)/tmp/test-github
TESTOUTDIR=/tmp/pykythe_test
BROWSE_PORT=8002
PYTHON3_EXE:=$(shell which python3.6)
SWIPL_EXE:=$(shell which swipl)
# COVERAGE=/usr/local/bin/coverage
# COVERAGE:=$(shell type -p coverage)  # doesn't work because "type" isn't a command
COVERAGE:=$(shell which coverage)
TIME=time

all_tests: test test_grammar test test_grammar  # pykythe_http_server

all_tests_plus: all_tests pyformat mypy

test: tests/test_pykythe.py \
		pykythe/ast_raw.py \
		pykythe/pod.py
	$(PYTHON3_EXE) -B tests/test_pykythe.py

# Test that all syntactic forms are processed:
test_grammar: verify-$(TEST_GRAMMAR_FILE3) verify-$(TEST_GRAMMAR_FILE2) verify-$(TEST_GRAMMAR_FILE)

# Reformat all the source code (uses .style.yapf)
pyformat:
	find . -type f -name '*.py' | grep -v $(TEST_GRAMMAR_DIR) | xargs yapf -i

yapf: pyformat

pylint:
	find . -type f -name '*.py' | grep -v $(TEST_GRAMMAR_DIR) | \
		grep -v snippets.py | xargs -L1 pylint --disable=missing-docstring

pyflakes:
	find . -type f -name '*.py' | grep -v $(TEST_GRAMMAR_DIR) | \
		grep -v snippets.py | xargs -L1 pyflakes

PYTYPE_DIR=/tmp/pykythe_pytype
PYTYPE_V=3.6
# Can't do the following because need to compile
# things like parser_ext:
#   PYTYPE=PYTHONPATH=$$(pwd)/../pytype ../pytype/scripts/pytype
# and PYTHONPATH seems to confuse other things in:N
#   PYTYPE=PYTHONPATH=$$(pwd)/../pytype/build/lib.linux-x86_64-2.7 ../pytype/scripts/pytype
# The following requires having done an install from ../pytype:
# PYTYPE=/usr/local/bin/pytype
PYTYPE=$(shell which pytype)
# TODO: in the following, it would be nice if we could remove the
#       "cd pykythe" and instead using the file name "pykythe/...py"
#       but that seems to upset pytype's imnport mechanism.

pytype: $(PYTYPE_DIR)/pykythe/__main__.pyi

$(PYTYPE_DIR)/%.pyi: %.py
	mkdir -p $(dir $@)
	-$(PYTYPE) -V$(PYTYPE_V) -P $(PYTYPE_DIR) $< -o $@

$(PYTYPE_DIR)/pykythe/ast.pyi: $(addprefix $(PYTYPE_DIR)/pykythe/,\
	pod.pyi)
$(PYTYPE_DIR)/pykythe/ast_cooked.pyi: $(addprefix $(PYTYPE_DIR)/pykythe/,\
	pod.pyi typing_debug.pyi ast.pyi)
$(PYTYPE_DIR)/pykythe/ast_raw.pyi: $(addprefix $(PYTYPE_DIR)/pykythe/,\
	pod.pyi typing_debug.pyi ast_cooked.pyi)
$(PYTYPE_DIR)/pykythe/__main__.pyi: $(addprefix $(PYTYPE_DIR)/pykythe/,\
	pod.pyi typing_debug.pyi ast_raw.pyi ast_cooked.pyi ast.pyi)

# TODO: --python-version=3.6  # conflict if python3.6 is not default python3
#       maybe --no-site-packages ?
# Anyway, mypy doesn't yet have a plugin for dataclasses. :(
MYPY=$(PYTHON3_EXE) $$(which mypy) --python-version=3.6 --strict-optional --check-untyped-defs --warn-incomplete-stub --warn-no-return --no-incremental --disallow-any-unimported --show-error-context --implicit-optional --strict --disallow-incomplete-defs
# TODO: --disallow-incomplete-defs  https://github.com/python/mypy/issues/4603
# TODO: --disallow-any-generics

mypy:
	$(MYPY) pykythe/__main__.py
	$(MYPY) tests/test_pykythe.py

lint: pylint

# Delete the files generated by test_grammar:
clean:
	$(RM) -r $(TESTOUTDIR)/$(TEST_GRAMMAR_FILE)-*.* \
		$(TESTOUTDIR)/$(TEST_GRAMMAR_FILE2)-*.* \
		$(TESTOUTDIR)/$(TEST_GRAMMAR_FILE3)-*.* \
		$(TESTOUTDIR)/graphstore/* $(TESTOUTDIR)/tables/* \
		$(PYTYPE_DIR) \
		.coverage htmlcov __pycache__
	-# $(RM) -r $(TESTOUTDIR)
	-# find $(TESTOUTDIR) -type f

$(TESTOUTDIR)/%-fqn.json: \
		$(TEST_GRAMMAR_DIR)/%.py \
		pykythe/__main__.py \
		scripts/decode_json.py \
		pykythe/ast_cooked.py \
		pykythe/ast_raw.py \
		pykythe/pod.py \
		Makefile
	mkdir -p $(TESTOUTDIR)
	$(TIME) $(PYTHON3_EXE) -B -m pykythe \
		--corpus='test-corpus' \
		--root='test-root' \
		--src="$<" \
		--out_fqn_expr="$@"

$(TESTOUTDIR)/%-kythe.json: $(TESTOUTDIR)/%-fqn.json \
		scripts/pykythe_post_process.pl scripts/must_once.pl \
		Makefile
	@# TODO: make this into a script (with a saved state (qsave_program/2 stand_alone).
	@# If you add </dev/null to the following, it'll keep going even on failure.
	@# ... without that, it'll stop, waiting for input
	@# If you add --quiet, you might be confused by this situation
	$(TIME) $(SWIPL_EXE) -O -s scripts/pykythe_post_process.pl "$<" >"$@" 2>"$@-error" </dev/null
	cat "$@-error"

%.json-decoded: %.json scripts/decode_json.py
	$(PYTHON3_EXE) -B scripts/decode_json.py <"$<" >"$@"

%-kythe.entries: %-kythe.json
	mkdir -p $(dir $<)
	$(ENTRYSTREAM_EXE) --read_json <"$<" >"$@"

.PHONY: verify-%
.SECONDARY: # %.entries %.json-decoded %.json

verify-%:  $(TESTOUTDIR)/%-kythe.entries $(TEST_GRAMMAR_DIR)/%.py $(TESTOUTDIR)/%-kythe.json $(TESTOUTDIR)/%-kythe.json-decoded
	$(VERIFIER_EXE) -check_for_singletons -goal_prefix='#-' "$(word 2,$^)" <"$(word 1,$^)"

prep_server: $(TESTOUTDIR)/$(TEST_GRAMMAR_FILE).nq.gz

%.nq.gz: %.entries
	rm -rf $(TESTOUTDIR)/graphstore $(TESTOUTDIR)/tables
	$(WRITE_ENTRIES_EXE) -graphstore $(TESTOUTDIR)/graphstore \
		<"$<"
	mkdir -p $(TESTOUTDIR)/graphstore $(TESTOUTDIR)/tables
	$(WRITE_TABLES_EXE) -graphstore=$(TESTOUTDIR)/graphstore -out=$(TESTOUTDIR)/tables
	$(TRIPLES_EXE) "$<" | \
		gzip >"$@"
	# 	$(TRIPLES_EXE) -graphstore $(TESTOUTDIR)/graphstore


run_server: prep_server
	$(HTTP_SERVER_EXE) -serving_table=$(TESTOUTDIR)/tables \
	  -public_resources=$(HTTP_SERVER_RESOURCES) \
	  -listen=localhost:$(BROWSE_PORT)

snapshot:
	rm -rf __pycache__
	git gc
	cd .. && tar --create --exclude=.cayley_history --exclude=.mypy_cache --exclude=__pycache__ --gzip --file \
		$(HOME)/Downloads/pykythe_$$(date +%Y-%m-%d-%H-%M).tgz pykythe
	ls -lh $(HOME)/Downloads/pykythe_*.tgz

ls_uris:
	$(KYTHE_EXE) -api $(TESTOUTDIR)/tables ls -uris

ls_decor:
	$(KYTHE_EXE) -api $(TESTOUTDIR)/tables decor kythe://test-corpus?path=$(TEST_GRAMMAR_DIR)/$(TEST_GRAMMAR_FILE).py

push_to_github:
	grep SUBMIT $$(find tests pykythe scripts test_data tests -type f); if [ $$? -eq 0 ]; then exit 1; fi
	@# The following are for the initial setup only:
	@#   mkdir -p $(TESTGITHUB)
	@#   rm -rf $(TESTGITHUB)/pykythe
	@#   cd $(TESTGITHUB) && git clone https://github.com/kamahen/pykythe.git
	@# The following is not needed ("git clone" sets this up):
	@#   git remote add origin https://github.com/kamahen/pykythe.git
	cd $(TESTGITHUB)/pykythe && git pull
	rsync -aAHX --exclude .git \
		--exclude .coverage --exclude htmlcov --exclude __pykythe__ \
		--exclude snippets.py \
		./ $(TESTGITHUB)/pykythe/
	rsync -aAHX --delete ../kythe $(TESTGITHUB)/
	-cd $(TESTGITHUB)/pykythe && git status
	-cd $(TESTGITHUB)/pykythe && git difftool --no-prompt --tool=tkdiff
	@echo '# pushd $(TESTGITHUB)/pykythe && git commit -mCOMMIT-MSG' -a
	@echo '# pushd $(TESTGITHUB)/pykythe && git push -u origin master'

triples: $(TESTOUTDIR)/$(TEST_GRAMMAR_FILE).nq.gz

pykythe_http_server: $(TESTOUTDIR)/$(TEST_GRAMMAR_FILE)-kythe.json scripts/pykythe_http_server.pl FORCE
	scripts/pykythe_http_server.pl \
		--port 8008 \
		--kythe $(TESTOUTDIR)/$(TEST_GRAMMAR_FILE)-kythe.json

FORCE:
.PHONY: FORCE


coverage:
	-# file:///home/peter/src/pykythe/htmlcov/index.html
	-# TODO: use the variables in the rule for $(TESTOUTDIR)/%-kythe.json
	-# TODO: run test_pykythe.py and add to coverage results
	$(PYTHON3_EXE) $(COVERAGE) run --branch -m pykythe \
		--corpus='test-corpus' --root='test-root' \
		--src="$(TEST_GRAMMAR_DIR)/py3_test_grammar.py" \
		--out_kythe=/dev/null --out_fqn_expr=/dev/null
	-# $(PYTHON3_EXE) $(COVERAGE) run --branch tests/test_pykythe.py
	$(COVERAGE) html
	rm -r pykythe/__pycache__
