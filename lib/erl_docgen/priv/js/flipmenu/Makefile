#
# %CopyrightBegin%
# 
# Copyright Ericsson AB 2009-2021. All Rights Reserved.
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# 
# %CopyrightEnd%
#
#
include $(ERL_TOP)/make/target.mk
include $(ERL_TOP)/make/$(TARGET)/otp.mk

# ----------------------------------------------------
# Application version
# ----------------------------------------------------
include ../../../vsn.mk
VSN=$(ERL_DOCGEN_VSN)

# ----------------------------------------------------
# Release directory specification
# ----------------------------------------------------
RELSYSDIR = $(RELEASE_PATH)/lib/erl_docgen-$(VSN)


# ----------------------------------------------------
# Target Specs
# ----------------------------------------------------


GIF_FILES = \
	flip_closed.gif \
	flip_open.gif \
	flip_static.gif

JS_FILES = \
	flipmenu.js

# ----------------------------------------------------
# FLAGS
# ----------------------------------------------------


# ----------------------------------------------------
# Targets
# ----------------------------------------------------
debug opt: 

DOC_TARGETS?=html

docs: $(DOC_TARGETS)

clean:
	$(RM) $(TARGET_FILES)


# ----------------------------------------------------
# Release Target
# ---------------------------------------------------- 
include $(ERL_TOP)/make/otp_release_targets.mk

release_spec: opt
	$(INSTALL_DIR) "$(RELSYSDIR)/priv/js/flipmenu"
	$(INSTALL_DATA) $(JS_FILES) $(GIF_FILES) "$(RELSYSDIR)/priv/js/flipmenu"

release_html_spec: html
	$(INSTALL_DIR) "$(RELEASE_PATH)/doc/js/flipmenu"
	$(INSTALL_DATA) $(JS_FILES) $(GIF_FILES) "$(RELEASE_PATH)/doc/js/flipmenu"
	$(INSTALL_DATA) ../highlight.js ../highlight.pack.js ../topbar.js "$(RELEASE_PATH)/doc/js/"

release_docs_spec: $(DOC_TARGETS:%=release_%_spec)

release_tests_spec:


