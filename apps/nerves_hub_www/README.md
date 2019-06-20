# NervesHubWWW

## Adding translations

### Replace the current text with a call to the gettext macro

Note: The extract and merge functionality only works if the macro is used.
So please do not use a function call like `NervesHubWWWWeb.Gettext.gettext "Name"` for translations.

Example:
```
  <%= label f, :username, "Name" %>
```

Becomes:
```
  <%= label f, :username, gettext "Name" %>
```

### Extract the translations to a .pot file

This creates a `.pot` file which is essentially a summary of all the places in
your code where you have used one of the gettext macros `gettext`, `ngettext`, `dgettext` or `dngettext`.

Run: `mix gettext.extract`


### Merge the translations into .po files

This creates/updates the `.po` files which are the files where your actual translations live.

It will create files if they do not already exist, and it will update files that do already exist.

Run `mix gettext.merge priv/gettext` to merge the `.pot` contents for all the supported locales.

Run `mix gettext.merge priv/gettext --locale {locale_name}` to merge the `.pot` contents for a new locale or a single existing locale.

Note that if you want some sort of "default translation", add them in the `.pot` file,
this will propogate that text to the individual `.po` files..

### Add the translated text

Add your translations by editing the values for `msgstr` in the `.po` files.

If no translation is given, the value contained in `msgid` will be used.

## Advanced translations

### Interpolated strings

This works a lot like the normal gettext functionality, the difference being that
you pass a value into the macro by binding it to a variable name (very similar to assigns in phoenix render functions).

You add such a translation by adding to the UI something like this:

```
<%= gettext("We would like to welcome you to the %{organization_name} family", organization_name: "Nerves Developers") %>
```

Now, run `gettext.extract` and `gettext.merge` as discussed before. This will add
the string to the `.pot` and `.po` files.

You can then add translations for the string by editing the `msgstr` in your `.po` files.

Translation definition:

```
msgid "We would like to welcome you to the %{organization_name} family"
msgstr "Ons wil you graag welkom heed by die %{organization_name} familie"

```

### Domain specific translations

By default, when using the `gettext` macro in our code, strings/tranlations gets
defined in `default.pot` and a `default.po` file for each locale.

When these files become too large, we can change over to domain based definition
by using the `dgettext` macro(and `dngettext` for plurals).

This causes certain translations to be moved to domain specific `.pot` and `.po`
files. Please see the gettext docs for more details, or take a look in nerves_hub_web
at the implimentation for "error" domain.

### Plural translations

The process for adding a plural to the translations is similar to what was discussed before.

Note that in the UI you use the macros that contain an `n` character such as `ngettext` and `dngettext`.

The `n` indicates that we are interested in a pluralized string.

Please see the gettext docs for more details.
