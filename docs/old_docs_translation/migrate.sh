#!/bin/bash

for lang in i18n/*; do
  lang=${lang%*/}
  lang=${lang##*/}
  for po in i18n/$lang/*.po; do
    fn=$(basename -- ${po%*.po})
    msgfmt -o i18n/$lang/LC_MESSAGES/$fn.mo $po
  done
done
