@echo off
rem Copy this file to r2-keys.bat and fill in your own R2 API token.
rem r2-keys.bat is ignored by git, so the keys stay on this PC.
set R2_ACCOUNT_ID=isi_account_id
set R2_ACCESS_KEY_ID=isi_access_key_id
set R2_SECRET_ACCESS_KEY=isi_secret_access_key
set R2_BUCKET=mymanual
rem Admin code of the server (same as the GitHub secret OWNER_CODE); used to
rem upload karyawan.xlsx and to warm new manuals.
set ADMIN_CODE=isi_kode_admin
