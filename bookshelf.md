---
layout: bookshelf
title: Bookshelf
permalink: /bookshelf/
---

{% comment %}

Add files under `_bookshelf`, in the format:

---
new: true
cover: /images/bookshelf/beginning_cpp_though_game_programming_4th_ed.jpg
description: A fun book to start C++ with; covers the language essentials with consistent progression, and uses example games that are simple enough to be thoroughly analyzed.
completed: 2019-01-07
---

Optionally, `cover_width` can be used to fit larger books (the height will stay constant, though).

{% endcomment %}

<link rel="stylesheet" href="/css/bookshelf.css">

{% comment %}

A simpler version of the logic is to store the last generated year, and generate a new one if different (or if the first), however, this can be unintuitive; this logic is also very generic.

{% endcomment %}

{% assign sorted_years = '' | split: ',' %}
{% for book in site.bookshelf %}
{%   assign completion_date = book.completed | date: '%Y' | split: ',' %}
{%   assign sorted_years = sorted_years | concat: completion_date | uniq | sort | reverse %}
{% endfor %}

{% assign sorted_books = site.bookshelf | sort: 'completed' | reverse %}

<div class="books">

{% for year in sorted_years %}
  <h2>{{year}}</h2>
  <ul class="bookshelf">
  {% for book in sorted_books %}
  {% assign book_year = book.completed | date: '%Y' %}
  {% if book_year == year %}
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
  {% endif %}
  {% endfor %}
  </ul>
  <div style="clear:both"></div>
{% endfor %}

</div>