// TODO move core routes to swift
const routes = {
  _: coreRoute,
};

async function loadRoutes() {
  console.log('called');
  // files is set from swift
  // Loop through route files & load
  for (const pkg of Object.keys(files)) {
    const code = files[pkg];
    const exported = {};
    try {
      eval(`((module) => {${code}})(exported)`);
    } catch (error) {
      console.error(`Error loading route for ${pkg}`);
      console.error(error);
      return;
    }
    if (typeof exported.exports !== 'function') {
      console.error(`Could not load route for ${pkg}`);
      return;
    }
    routes[pkg] = await exported.exports({
      LevelUpBackend: LevelJS,
      pathPrefix: pkg + '/',
    });
  }
}

/*
response obj fields
{
  id, // passed in value
  status, // Code
  body, // String
}
*/
function response(obj) {
  window.webkit.messageHandlers.response.postMessage(JSON.stringify(obj));
}

function request({id, route, body}) {
  console.log(id, route, body)
  const path = route.split('/').filter((s)=>s !== '');

  if (path.length === 0) {
    return response({
      id,
      status: 404,
      body: JSON.stringify({message: 'No Route Specified'}),
    });
  }

  const pkg = path.shift().toLowerCase();
  if (routes[pkg] === undefined) {
    return response({
      id,
      status: 404,
      body: JSON.stringify({message: 'No Route for Package'}),
    });
  }

  routes[pkg]({
      route: `/${path.join('/')}`,
      body: (body) ? JSON.parse(body) : {},
    })
    .then((body) => {
      response({
        id,
        status: 200,
        body: JSON.stringify(body),
      });
    })
    .catch((error) => {
      response({
        id,
        status: error.status || 500,
        body: JSON.stringify({message: error.message}),
      });
    })
}

async function coreRoute({route, body}) {
  switch(route) {
    case '/package/install':
      return installPackage(body);
    case '/package/uninstall':
      return uninstallPackage(body);
    default:
      const error = new Error('Unknown Route');
      error.status = 404;
      throw error;
  }
}

async function installPackage({name, version = 'latest'}) {
  console.log(`installing package ${name}`);
  // TODO
  return true;
};

async function uninstallPackage({name}) {
  console.log(`uninstalling package ${name}`);
  return true;
};
