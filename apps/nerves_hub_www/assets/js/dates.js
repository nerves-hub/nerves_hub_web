document.querySelectorAll(".date-time").forEach((d) => {
  const date =  new Date(d.innerHTML)
  d.innerHTML = date.toLocaleString('en-US', {timeZoneName: 'short'})
})
