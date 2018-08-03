

function attachToAjaxForm(formId, dataset) {
  var success_url = dataset['successRedirectUrl'];

  $(formId).ajaxForm({
    type: 'POST',
    beforeSend:function(jqXHR, settings) {
      return true;
    },
    success: function(data, textStatus, jqXHR) {
      if (data["status"] == "err") {
        $("#js_modal_content").html(data["data"]);
        attachToAjaxForm(formId, dataset);
      } else if (success_url) {
        window.location.href = success_url;
        $('#js_modal_holder').modal('hide');
      }
    },
    error: function(jqXHR, textStatus, errorThrown) {
      alert('ajax submit failed: ' + textStatus);
      $('#js_modal_holder').modal('hide');
    },
    complete:function(jqXHR, textStatus) {
    }
  });
}

function run_ajax(targ) { 
  var dataset = targ.dataset;

  $.ajax({
    url: targ.dataset['modalSrcUrl'],
    beforeSend: function(jqXHR, settings){
      return true;
    },
    success: function(data, textStatus, jqXHR) {
      $("#js_modal_content").html(data);
      $('#js_modal_holder').modal('show');
      attachToAjaxForm('#js_modal_content form', dataset);
    },
    error: function(jqXHR, textStatus, errorThrown){
      alert('page load failed: ' + targ.dataset['url']);
      return true;
    },
    complete:function(jqXHR, textStatus) {      
      return true;
    }
  });
  return true;
}



$(function() {
  $(".action_btn").click(function(event) {
   if ( event.target.dataset['modalSrcUrl']) {
      run_ajax(event.target);
      return false;
    }
  })
  return true;
});