$(function () {
  var $el = $(".summary li.enqueued > a"),
      url = $el.attr("href").replace(/\/queues$/, "/enhanced-queues");
  $el.attr("href", url);
});
