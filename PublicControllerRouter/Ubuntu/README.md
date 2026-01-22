
Install Open Ziti Controller

Use the OpenZiti Install script

```
curl -sSL https://get.openziti.io/install.bash | sudo bash -s openziti-controller
```

Generate a configuration interactively (populate /opt/openziti/etc/controller/bootstrap.env for non-interactively)

```
sudo /opt/openziti/etc/controller/bootstrap.bash
```


```
sudo chown ziti:ziti /opt/openziti/bbolt.db
sudo chown ziti:ziti /opt/openziti/
```

```
sudo systemctl enable --now ziti-controller.service
```


Router


```
wget https://github.com/netfoundry/ziti_router_auto_enroll/releases/latest/download/ziti_router_auto_enroll.tar.gz
tar xf ziti_router_auto_enroll.tar.gz
```

```
sudo ./ziti_router_auto_enroll -f -n --controller 68.183.52.206 --controllerFabricPort 8440 --controllerMgmtPort 8441 --adminUser admin --adminPassword Test@123 --assumePublic --disableHealthChecks --routerName pub-er 
```