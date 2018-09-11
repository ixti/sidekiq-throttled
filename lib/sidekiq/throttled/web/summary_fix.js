document.addEventListener("DOMContentLoaded", function () {
  var elem = document.querySelector(".summary li.enqueued > a"), href;

  if (!elem) {
    console.warn("[Sidekiq::Threshold] cannot find summary bar link to fix");
  } else {
    href = elem.getAttribute("href").toString();
    elem.setAttribute("href", href.replace(/\/queues$/, "/enhanced-queues"));
  }
});
