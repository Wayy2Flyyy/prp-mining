const dist = document.querySelector("#dist");
const drillOverlay = document.querySelector(".drillOverlay");
const drillOverlayTexture = document.querySelector(".drillOverlayTexture");

document.addEventListener("DOMContentLoaded", () => {
    try {
        fetch(`https://prp-mining/prp-mining:duiLoaded`, {method: "POST", body: "{}"});
    } catch(e){}
});
function setPercentage(percentage) {
    drillOverlay.style.backgroundColor = `rgba(218, 33, 33, ${percentage / 100})`;
}

let brokenInterval = undefined
function setBroken(broken) {
    if (broken && !brokenInterval) {
        let colorSwitch = false;
        brokenInterval = setInterval(() => {
            colorSwitch = !colorSwitch;
            drillOverlay.style.transition = "background-color 0.5s";
            drillOverlay.style.backgroundColor = `rgba(218, 33, 33, ${colorSwitch ? 1.0 : 0})`;
        }, 500);
    } else if (!broken && brokenInterval) {
        clearInterval(brokenInterval);
        brokenInterval = undefined;
        drillOverlay.style.transition = "none";
        drillOverlay.style.backgroundColor = `rgba(218, 33, 33, 0)`;
    }
}

window.addEventListener("message", e => {
    const item = e.data;

    if(item.event === "setPercentage") {
        setPercentage(item.percentage);
    }
    if(item.event === "setBroken") {
        setBroken(item.broken);
    }
    if(item.event === "setOverlayColor") {
        drillOverlayTexture.style.backgroundColor = item.color;
    }
})
