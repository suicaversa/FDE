var map = null;
var currentInfoWindow = null;
var markers = [];

function initialize(){
  map = new google.maps.Map(document.getElementById('map'), {
    zoom: 4,
    center: {lat: 35.679801, lng: 139.739525} // NagatachoGRID
  });
}

$(function(){
    $.ajax({
      url: "./list"
    }).done(function(data){
      $('.filelist').html(data);
      console.log("Ajax: Successfully fetched.");
    }).fail(function( jqXHR, textStatus ) {
      $('.filelist').html( "Ajax: Request failed: " + textStatus );
    });;

    $(document).on('click', '.flash', function(){
      $(this).fadeOut();
    });

    function createPins(url) {
      var mapDatas = [];
      $.ajax({
        dataType: "json",
        url: url
      }).done(function(datas){
        $.each(datas, function(k, data){
          mapDatas.push({
            created_time: data["created_time"],
            message: data["message"] || "",
            name: data["name"],
            latitude: data["latitude"],
            longitude: data["longitude"],
            images: data["images"]
          });
        });
        console.log("MapAjax: Successfully fetched.");

        $.each(markers, function(k, m){
          m.setMap(null);
        });
        markers = [];

        $.each(mapDatas, function(k, mapData){
          var infowindow = new google.maps.InfoWindow({
            content: mapData["created_time"] + "<br>" + mapData["message"].replace(/\n/, "<br>") + mapData["images"].join("<br>")
          });

          var marker = new google.maps.Marker({
            position: {lat: mapData["latitude"], lng: mapData["longitude"]},
            map: map,
            title: mapData["name"]
          });
          markers.push(marker);
          marker.addListener('click', function() {
            if(currentInfoWindow) currentInfoWindow.close();
            currentInfoWindow = infowindow;
            infowindow.open(map, marker);
          });
        });

      }).fail(function( jqXHR, textStatus ) {
        console.log( "MapAjax: Request failed: " + textStatus );
      });;
    }

    $(document).on('click', '.map-item', function(){
      createPins($(this).data("url"));
    });
  });
