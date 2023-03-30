## Initial SQL setup

Command:

```
createuser -s dablang_ex0004
dropdb dablang_ex0004
createdb dablang_ex0004
[copy initial sql]
pbpaste | psql --user dablang_ex0004 dablang_ex0004
```

SQL:

```
CREATE SEQUENCE books_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

CREATE TABLE books (
    id integer NOT NULL,
    title character varying NOT NULL,
    author character varying,
    year integer
);

ALTER TABLE ONLY books ALTER COLUMN id SET DEFAULT nextval('books_id_seq'::regclass);

ALTER TABLE ONLY books ADD CONSTRAINT books_pkey PRIMARY KEY (id);

INSERT INTO books (title, author, year) VALUES
  ('The motor boys on the wing', 'Clarence Young', 1912),
  ('Choice of choices', 'John Haddad', 1905),
  ('The lotus of the Nile', 'Arthur Eaton', 1907),
  ('Tricky case', 'Year is null', NULL),
  ('Missing author', NULL, 1410);
```

Inline:
```
createuser -s dablang_ex0004
dropdb dablang_ex0004
createdb dablang_ex0004
echo H4sIAL7pJGQAA31RwW6cMBC971fMjV2JQ6hSRU1OjtfR0oI3AdOWU+SAu1hLcGubJPx9bcMmVSOFE5557828N7ggiBEoyV1FKCbwoNTR3Mv23og/K3BfyVDB4EfKdpCEQkpxQXJCGVzXS4nuIU/pd5RV5PWNfr69McI7AsnVaoXncQxdZ8ssWAeIbEEOVhyEdmwGtMqyODSstL2ApuOaN9Z1n7ie5HD4D8VH2yn9HjZ3J8H1SX61cWugjJFi2WJPs3pZZS7jfVbl1G9UEgZbcoOqjMEgXuwT79fRvwlFl5daHJqeG/OR7HbrRGnJCpS62GaB30cxwW2R5qio4RupYS1br5HSkrjAHXB/CihEEC8e4+BmAyHd0tlbR6wT8Kis8/+gJgNqAOsqz85+FEOEe67F0Aio1RgqyZfk0yYOTNwp6Trql0vO/xlP+Kq6AXa8bXkb0GefF7Sf0ys7Gk/wI6jshWcgbbtRA+FWDTPl4kTRsjlO0HATgHU4hIFh7Hv39vdbgLk0xp91Nrn0nNR5cra5+gvc8/4hpQIAAA== | base64 -d | gunzip | psql --user dablang_ex0004 dablang_ex0004

```
