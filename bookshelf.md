---
layout: page
title: Bookshelf
permalink: /bookshelf/
---

{% comment %}

Add files under `_books`, in the format:

---
new: true
cover: /images/books/beginning_cpp_though_game_programming_4th_ed.jpg
description: A fun book to start C++ with; covers the language essentials with consistent progression, and uses example games that are simple enough to be thoroughly analyzed.
completed: 2019-01-07
---

Optionally, `cover_width` can be used to fit larger books (the height will stay constant, though).

{% endcomment %}

<link rel="stylesheet" href="/css/bookshelf.css">

{% assign sorted_books = site.books | sort: 'completed' | reverse %}
{% for book in sorted_books %}
<ul class="bookshelf">
  <li class="bookshelf-book">
   {% if book.new %}
    <div class="ribbon-new">
      <div>New</div>
    </div>
   {% endif %}
    <img src="{{ book.cover }}"
    {% if book.cover_width %}
      width="{{ book.cover_width }}"
    {% endif %}
    />
    <div class="bookshelf-caption bottom-to-top">
      <p>{{ book.description }}</p>
    </div>
  </li>
</ul>
{% endfor %}

<div style="clear: left"></div>
