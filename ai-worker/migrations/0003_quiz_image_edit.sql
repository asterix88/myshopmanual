-- "Atur gambar" v2 (Anas, 7 Nov 2026): the admin's picture edits are kept as
-- data so the editor reopens on them, and a labelled photo's question keeps
-- its "[X]" text so the letter can change after each edit.
ALTER TABLE question ADD COLUMN image_edit TEXT;       -- JSON from the app's editor
ALTER TABLE question ADD COLUMN prompt_template TEXT;  -- prompt with [X], before the letter went in
