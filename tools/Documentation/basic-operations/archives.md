# 📚 Reading Archives

## Using the Archive Index

The main page will show all the Archives loaded into the application, sorted by name.  

![Archive Index in Thumbnail mode](<https://raw.githubusercontent.com/Difegue/LANraragi/dev/tools/\_screenshots/archive\_thumb.png>)  

You can customize display options to show the index in compact mode, as well as to select which namespace to use in the two extra columns.  

![Customized compact mode to sort by ratings](../.screenshots/ratings.png)  

The topmost **carousel** view will show random archives from your current search in both thumbnail and compact modes -- It can also be configured to show New or Untagged archives instead.  

![Index page of a regular LRR install in compact mode](<https://raw.githubusercontent.com/Difegue/LANraragi/dev/tools/\_screenshots/archive\_list.png>)

{% hint style="info" %}
Don't forget you can **right-click** archives to show a context menu, allowing you to edit/download/delete them, or to add them to a category.
{% endhint %}

When reading an archive, it is automatically extracted to a temporary folder.  
This folder is then simply loaded into the built-in Web Reader.  
The temporary folder will clean up on its own when it reaches a large enough size, so there's no need to worry about your disk filling up over time.

## Web Reader Options

In the reader, you can use the keyboard arrows or the built-in arrow icons to move from page to page.  
You can also simply click the right or left side of the image.  
When reading an archive, the three button icons on the rightside of the page offer various options.

![Reader View](../.screenshots/reader.jpg)

You can click the information icon on the right-side of the Reader to get a quick refresher about its controls.  
The Reader Options button shows the various options you can toggle to change the reading experience. (Double page, Japanese read order, etc.)

The Page Overlay button (also actionable by pressing **CTRL**) will show all the pages of the current archive, allowing for quick navigation and preview.

![Reader with overlay](https://raw.githubusercontent.com/Difegue/LANraragi/dev/tools/\_screenshots/reader\_overlay.jpg)

Starting with 0.7.8, you can also quickly check the metadata here.

The Reader comes with its own set of clientside options to customize the reading experience as you want.

![Reader Options](../.screenshots/reader\_options.png)

If "Progression Tracking" is enabled, when you close and reopen the archive, it'll show you the page you last stopped at.

## Non-Web Reader (Third-Party applications)

If you want to use a third-party application to read your archives, you can use the software listed in the following page:

{% content-ref url="../advanced-usage/external-readers.md" %}
[external-readers.md](../advanced-usage/external-readers.md)
{% endcontent-ref %}
