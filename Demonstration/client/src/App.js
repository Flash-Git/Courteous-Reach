import React, { Component } from 'react';
import Navbar from './components/Navbar';
import Landing from './components/Landing';
import Footer from './components/Footer';

import { Provider } from "react-redux";
import store from "./store";

import './App.css';

class App extends Component {
  render(){
    return(
      <Provider store={store}>
        <div className="App">
          <Navbar />
          <Landing />
          <Footer />
        </div>
      </Provider>
    );
  }
}

export default App;