#!/bin/bash

rsync -aW --delete template.app/ build.app/
cargo install --locked --path ../gephgui-wry